#' Create a Loro document
#'
#' A `loro_doc` is a handle to a Loro CRDT document held in Rust. It has
#' reference semantics: functions that edit a document modify it in place
#' and return it invisibly, so copies made with `=` refer to the same
#' document. Use [`doc_fork()`] for an independent replica.
#'
#' @param peer_id Optional peer id identifying this replica: a whole
#'   number or a string of digits (peer ids are unsigned 64-bit integers,
#'   so large ids must be given as strings). A random id is used when
#'   `NULL`.
#'
#' @return A `loro_doc` object.
#'
#' @examples
#' doc = loro_doc()
#' text_insert(doc_text(doc), 1, "Hello")
#' text_get(doc_text(doc))
#'
#' @export
loro_doc = S7::new_class(
  "loro_doc",
  package = "creditor",
  properties = list(ptr = S7::class_any),
  constructor = function(peer_id = NULL) {
    ptr = loro_doc_new_impl()
    if (!is.null(peer_id)) {
      loro_doc_set_peer_id_impl(ptr, as_peer_id(peer_id))
    }
    S7::new_object(S7::S7_object(), ptr = ptr)
  }
)

doc_from_ptr = function(ptr) {
  doc = loro_doc()
  doc@ptr = ptr
  doc
}

as_peer_id = function(peer_id) {
  if (is.character(peer_id) && length(peer_id) == 1 && grepl("^[0-9]+$", peer_id)) {
    return(peer_id)
  }
  if (
    is.numeric(peer_id) && length(peer_id) == 1 && !is.na(peer_id) &&
      peer_id >= 0 && peer_id == trunc(peer_id) && peer_id < 2^53
  ) {
    return(format(peer_id, scientific = FALSE))
  }
  cli::cli_abort(
    "{.arg peer_id} must be a non-negative whole number or a string of digits.",
    call = NULL
  )
}

check_doc = function(doc, call = sys.call(-1)) {
  if (!S7::S7_inherits(doc, loro_doc)) {
    cli::cli_abort(
      "{.arg doc} must be a {.cls loro_doc}, not {.obj_type_friendly {doc}}.",
      call = call
    )
  }
  invisible(doc)
}

#' Document identity, replicas, and contents
#'
#' @description
#' * `doc_peer_id()` returns the peer id of this replica as a string.
#' * `doc_fork()` returns an independent replica with the same history
#'   and a new peer id. With `at`, the replica holds the document as it
#'   was at that version.
#' * `doc_commit()` commits pending edits as one change, optionally
#'   labeled with a `message` that is kept in the history and shown by
#'   [`doc_changes()`]. An `origin` is a label for this commit that is
#'   not stored or synchronized: it is passed to subscribers on this
#'   replica as `event$origin`, so they can tell where a change came
#'   from, and an undo manager can be told to ignore commits by origin. Edits are also committed implicitly on export,
#'   import, and checkout.
#' * `doc_value()` returns the whole document as a named list with one
#'   element per root container.
#' * `doc_get_path()` returns the value at a slash-separated path such
#'   as `"note/items/1"`: a root container name, then map keys, 0-based
#'   list positions, or tree node ids. Containers are returned as
#'   handles, and `NULL` means nothing is there.
#' * `doc_jsonpath()` returns a list of everything matching a JSONPath
#'   expression such as `"$.note.items[*]"`.
#'
#' @param doc A [`loro_doc`].
#' @param at A version from [`doc_frontiers()`] to fork at, or `NULL`
#'   for the current version.
#' @param message A string describing the change, or `NULL`.
#' @param origin A string labeling the source of the commit, or `NULL`.
#' @param path A path or JSONPath expression, as a string.
#'
#' @return `doc_peer_id()` returns a string, `doc_fork()` a new
#'   `loro_doc`, `doc_commit()` returns `doc` invisibly, and
#'   `doc_value()` a named list. `doc_get_path()` returns a value or
#'   container handle, and `doc_jsonpath()` a list of them.
#'
#' @examples
#' doc = loro_doc(peer_id = 1)
#' text_insert(doc_text(doc), 1, "Hello")
#' doc_peer_id(doc)
#' doc_value(doc)
#'
#' @name doc
NULL

#' @rdname doc
#' @export
doc_peer_id = function(doc) {
  check_doc(doc)
  loro_doc_peer_id_impl(doc@ptr)
}

#' @rdname doc
#' @export
doc_fork = function(doc, at = NULL) {
  check_doc(doc)
  if (!is.null(at)) {
    check_frontiers(at, "at")
  }
  fork = doc_from_ptr(loro_doc_fork_impl(doc@ptr, at))
  deliver_events()
  fork
}

#' @rdname doc
#' @export
doc_commit = function(doc, message = NULL, origin = NULL) {
  check_doc(doc)
  if (!is.null(message)) {
    message = check_string(message, "message")
  }
  if (!is.null(origin)) {
    origin = check_string(origin, "origin")
  }
  loro_doc_commit_impl(doc@ptr, message, origin)
  deliver_events()
  invisible(doc)
}

#' @rdname doc
#' @export
doc_value = function(doc) {
  check_doc(doc)
  loro_doc_value_impl(doc@ptr)
}

#' @rdname doc
#' @export
doc_get_path = function(doc, path) {
  check_doc(doc)
  container_from_ref(loro_doc_get_path_impl(doc@ptr, check_string(path, "path")))
}

#' @rdname doc
#' @export
doc_jsonpath = function(doc, path) {
  check_doc(doc)
  lapply(loro_doc_jsonpath_impl(doc@ptr, check_string(path, "path")), container_from_ref)
}

#' Synchronize documents
#'
#' @description
#' Replicas exchange state as raw vectors, which can be written to disk
#' or sent over any transport.
#'
#' * `doc_export()` serializes a document, in one of three modes:
#'   * `"snapshot"`: the full contents and history.
#'   * `"updates"`: the changes made since the version `from`, or the
#'     complete history when `from` is `NULL`.
#'   * `"shallow_snapshot"`: the contents plus only the history after
#'     the version `since`. Dropping old history can make the export
#'     much smaller for a document with a long history, but a document
#'     loaded from it cannot check out versions before `since` or merge
#'     edits that branch off before it.
#' * `doc_import()` merges a snapshot or updates into a document.
#'   Importing is commutative and idempotent, so replicas that have seen
#'   the same updates hold the same contents. `bytes` may also be a list
#'   of raw vectors, which are imported together in one step.
#' * `doc_version()` returns the document's current version (an encoded
#'   version vector) for use as the `from` argument of a later export.
#' * `doc_is_shallow()` reports whether a document lacks its early
#'   history because it was loaded from a shallow snapshot.
#' * `blob_metadata()` describes an exported raw vector without
#'   importing it.
#' * `doc_export_json()` and `doc_import_json()` exchange changes as
#'   JSON text. This is larger than the binary format but readable, and
#'   useful for inspection and debugging.
#'
#' @section Import status:
#' `doc_import()` and `doc_import_json()` invisibly return a list of two
#' data frames, `success` and `pending`, each with columns `peer`,
#' `start`, and `end` giving a range of that peer's operation counters.
#' `success` holds the operations that were applied. `pending` holds
#' operations that arrived before the changes they depend on; they are
#' kept and applied automatically once the missing changes are
#' imported. A non-empty `pending` means an earlier update was lost or
#' is still in transit.
#'
#' @param doc A [`loro_doc`].
#' @param mode One of `"snapshot"`, `"updates"`, or
#'   `"shallow_snapshot"`.
#' @param from A version returned by `doc_version()`, typically that of
#'   the replica the updates are destined for. Only used when `mode` is
#'   `"updates"`. For `doc_export_json()`, the version to start from, or
#'   `NULL` for the beginning.
#' @param since A version from [`doc_frontiers()`]. Only used when `mode`
#'   is `"shallow_snapshot"`; `NULL` keeps no history before the current
#'   version.
#' @param to A version returned by `doc_version()` to stop at, or `NULL`
#'   for the latest.
#' @param bytes A raw vector produced by `doc_export()`, or for
#'   `doc_import()` a list of them.
#' @param json A string produced by `doc_export_json()`.
#'
#' @return `doc_export()` and `doc_version()` return raw vectors.
#'   `doc_import()` and `doc_import_json()` invisibly return an import
#'   status; see the Import status section. `doc_is_shallow()` returns a
#'   logical, `doc_export_json()` a string, and `blob_metadata()` a list
#'   with `mode`, `changes` (the number of changes), `start_timestamp`
#'   and `end_timestamp`, and the versions `start_frontiers`,
#'   `start_version`, and `end_version`.
#'
#' @examples
#' a = loro_doc()
#' text_insert(doc_text(a), 1, "Hello")
#'
#' b = loro_doc()
#' doc_import(b, doc_export(a))
#'
#' text_insert(doc_text(a), 6, " world")
#' text_insert(doc_text(b), 1, ">> ")
#'
#' doc_import(b, doc_export(a, "updates", from = doc_version(b)))
#' doc_import(a, doc_export(b, "updates", from = doc_version(a)))
#' text_get(doc_text(a))
#' text_get(doc_text(b))
#'
#' small = doc_export(a, "shallow_snapshot")
#' blob_metadata(small)$mode
#'
#' @name doc_sync
NULL

import_status = function(status) {
  lapply(status, function(range) {
    data.frame(peer = range$peer, start = range$start, end = range$end)
  })
}

#' @rdname doc_sync
#' @export
doc_export = function(
  doc,
  mode = c("snapshot", "updates", "shallow_snapshot"),
  from = NULL,
  since = NULL
) {
  check_doc(doc)
  mode = match.arg(mode)
  if (!is.null(from) && !is.raw(from)) {
    cli::cli_abort("{.arg from} must be a raw vector from {.fn doc_version} or {.code NULL}.")
  }
  if (!is.null(since)) {
    check_frontiers(since, "since")
  }
  bytes = loro_doc_export_impl(doc@ptr, mode, from, since)
  deliver_events()
  bytes
}

#' @rdname doc_sync
#' @export
doc_import = function(doc, bytes) {
  check_doc(doc)
  status = if (is.raw(bytes)) {
    loro_doc_import_impl(doc@ptr, bytes)
  } else if (is.list(bytes) && all(vapply(bytes, is.raw, logical(1)))) {
    loro_doc_import_batch_impl(doc@ptr, bytes)
  } else {
    cli::cli_abort(
      "{.arg bytes} must be a raw vector from {.fn doc_export}, or a list of them."
    )
  }
  deliver_events()
  invisible(import_status(status))
}

#' @rdname doc_sync
#' @export
doc_version = function(doc) {
  check_doc(doc)
  loro_doc_version_impl(doc@ptr)
}

#' @rdname doc_sync
#' @export
doc_is_shallow = function(doc) {
  check_doc(doc)
  loro_doc_is_shallow_impl(doc@ptr)
}

#' @rdname doc_sync
#' @export
blob_metadata = function(bytes) {
  if (!is.raw(bytes)) {
    cli::cli_abort("{.arg bytes} must be a raw vector from {.fn doc_export}.")
  }
  meta = loro_blob_metadata_impl(bytes)
  for (field in c("start_timestamp", "end_timestamp")) {
    value = meta[[field]]
    if (value == 0) {
      value = NA_real_
    }
    meta[[field]] = as.POSIXct(value, origin = "1970-01-01", tz = "UTC")
  }
  meta
}

#' @rdname doc_sync
#' @export
doc_export_json = function(doc, from = NULL, to = NULL) {
  check_doc(doc)
  for (arg in c("from", "to")) {
    value = get(arg)
    if (!is.null(value) && !is.raw(value)) {
      cli::cli_abort("{.arg {arg}} must be a raw vector from {.fn doc_version} or {.code NULL}.")
    }
  }
  json = loro_doc_export_json_impl(doc@ptr, from, to)
  deliver_events()
  json
}

#' @rdname doc_sync
#' @export
doc_import_json = function(doc, json) {
  check_doc(doc)
  status = loro_doc_import_json_impl(doc@ptr, check_string(json, "json"))
  deliver_events()
  invisible(import_status(status))
}

S7::method(print, loro_doc) = function(x, ...) {
  value = doc_value(x)
  cli::cli_text("{.cls loro_doc} peer {doc_peer_id(x)}")
  if (length(value) == 0) {
    cli::cli_text("(empty)")
  } else {
    utils::str(value, give.head = FALSE, no.list = TRUE)
  }
  invisible(x)
}
