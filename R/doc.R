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
#' text_insert(doc, 1, "Hello")
#' text_get(doc)
#'
#' # the same, through a handle to the root text container
#' text = doc_text(doc)
#' text_push(text, " world")
#' text_get(text)
#'
#' @export
loro_doc = S7::new_class(
  "loro_doc",
  package = "creditor",
  properties = list(ptr = S7::class_any, state = S7::class_environment),
  constructor = function(peer_id = NULL) {
    ptr = loro_doc_new_impl()
    if (!is.null(peer_id)) {
      loro_doc_set_peer_id_impl(ptr, as_peer_id(peer_id))
    }
    S7::new_object(S7::S7_object(), ptr = ptr, state = new.env(parent = emptyenv()))
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

check_doc = function(doc, arg = "doc", call = rlang::caller_env()) {
  if (!S7::S7_inherits(doc, loro_doc)) {
    cli::cli_abort(
      "{.arg {arg}} must be a {.cls loro_doc}, not {.obj_type_friendly {doc}}.",
      call = call
    )
  }
  invisible(doc)
}

#' Document identity, replicas, and contents
#'
#' @description
#' * `doc_peer_id()` returns the peer id of this replica as a string,
#'   and `doc_set_peer_id()` changes it. Two replicas must never edit
#'   under the same peer id.
#' * `doc_fork()` returns an independent replica with the same history
#'   and a new peer id. With `at`, the replica holds the document as it
#'   was at that version.
#' * `doc_commit()` commits pending edits as one change, optionally
#'   labeled with a `message` that is kept in the history and shown by
#'   [`doc_changes()`]. An `origin` is a label for this commit that is
#'   not stored or synchronized: it is passed to subscribers on this
#'   replica as `event$origin`, so they can tell where a change came
#'   from, and an undo manager can be told to ignore commits by origin.
#'   A `timestamp` is stored with the change in place of the current
#'   time, whether or not [`doc_record_timestamps()`] is on; Loro keeps
#'   timestamps non-decreasing, so one earlier than the latest existing
#'   timestamp is replaced by that latest one. Edits are also committed implicitly on export,
#'   import, and checkout.
#' * `doc_value()` returns the whole document as a named list with one
#'   element per root container. It is an error if containers are
#'   nested more than 1000 levels deep.
#' * `doc_get()` returns what is found by following a path into the
#'   document, one step per argument, as in `doc_get(doc, "note",
#'   "items", 2)`: the name of a root container, then a string for each
#'   map key or tree node id (which leads to the node's metadata map)
#'   and a 1-based number for each list position. Containers are
#'   returned as handles, and `NULL` means nothing is there. Unlike
#'   [`doc_map()`] and its siblings, it never creates a container.
#' * `doc_jsonpath()` returns a list of everything matching a JSONPath
#'   expression such as `"$.note.items[*]"`. JSONPath is its own
#'   language, so list positions inside it are 0-based. Loro does not support
#'   every JSONPath feature: a query that has to descend into a tree
#'   container, or that uses the `match()` or `search()` functions, is
#'   an error.
#'
#' @param doc A [`loro_doc`].
#' @param at A version from [`doc_frontiers()`] to fork at, or `NULL`
#'   for the current version.
#' @param message A string describing the change, or `NULL`.
#' @param origin A string labeling the source of the commit, or `NULL`.
#' @param timestamp The time to record for the commit, as a `POSIXct`
#'   or a number of seconds since 1970, or `NULL`.
#' @param peer_id A peer id: a whole number or a string of digits.
#' @param ... The steps of a path: strings and whole numbers. These
#'   are [dynamic dots][rlang::dyn-dots], so a path held in a list can
#'   be spliced in with `!!!`.
#' @param path A JSONPath expression, as a string.
#'
#' @return `doc_set_peer_id()` returns `doc` invisibly.
#'   `doc_peer_id()` returns a string, `doc_fork()` a new
#'   `loro_doc`, `doc_commit()` returns `doc` invisibly, and
#'   `doc_value()` a named list. `doc_get()` returns a value or
#'   container handle, and `doc_jsonpath()` a list of them.
#'
#' @examples
#' doc = loro_doc(peer_id = 1)
#' text_insert(doc, 1, "Hello")
#' doc_peer_id(doc)
#' doc_value(doc)
#'
#' note = doc_map(doc, "note")
#' note$items = loro_list("milk", "eggs")
#' doc_get(doc, "note", "items", 2)
#' doc_jsonpath(doc, "$.note.items[*]")
#'
#' @name doc
NULL

#' @rdname doc
#' @export
doc_peer_id = function(doc) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  loro_doc_peer_id_impl(doc@ptr)
}

#' @rdname doc
#' @export
doc_set_peer_id = function(doc, peer_id) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  loro_doc_set_peer_id_impl(doc@ptr, as_peer_id(peer_id))
  invisible(doc)
}

#' @rdname doc
#' @export
doc_fork = function(doc, at = NULL) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  if (!is.null(at)) {
    check_frontiers(at, "at")
    if (loro_doc_is_shallow_impl(doc@ptr)) {
      cli::cli_abort(
        c(
          "A shallow document cannot be forked at a version.",
          i = "Use {.code doc_fork(doc)} to fork it at its current version."
        )
      )
    }
  }
  fork = doc_from_ptr(loro_doc_fork_impl(doc@ptr, at))
  fork
}

#' @rdname doc
#' @export
doc_commit = function(doc, message = NULL, origin = NULL, timestamp = NULL) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  if (!is.null(message)) {
    message = check_string(message, "message")
  }
  if (!is.null(origin)) {
    origin = check_string(origin, "origin")
  }
  if (!is.null(timestamp)) {
    if (inherits(timestamp, "POSIXct")) {
      timestamp = as.numeric(timestamp)
    }
    if (!is.numeric(timestamp) || length(timestamp) != 1 || !is.finite(timestamp) || timestamp < 0) {
      cli::cli_abort(
        "{.arg timestamp} must be a single {.cls POSIXct} or a non-negative number of seconds."
      )
    }
    timestamp = floor(timestamp)
  }
  loro_doc_commit_impl(doc@ptr, message, origin, timestamp)
  invisible(doc)
}

#' @rdname doc
#' @export
doc_value = function(doc) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  loro_doc_value_impl(doc@ptr)
}

#' @rdname doc
#' @export
doc_get = function(doc, ...) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  path = unnamed_values(...)
  is_step = function(step) {
    length(step) == 1 && !is.na(step) &&
      (is.character(step) || (is.numeric(step) && step == trunc(step)))
  }
  if (length(path) == 0 || !all(vapply(path, is_step, logical(1)))) {
    cli::cli_abort("{.arg ...} must be one or more path steps, each a string or a whole number.")
  }
  root = path[[1]]
  if (!is.character(root)) {
    cli::cli_abort("The first path step must be the name of a root container.")
  }
  root = as_utf8(root, "...")
  if (grepl("/", root, fixed = TRUE)) {
    return(NULL)
  }
  at = container_from_ref(loro_doc_get_path_impl(doc@ptr, root))
  for (step in path[-1]) {
    at = get_step(at, step)
    if (is.null(at)) {
      break
    }
  }
  at
}

get_step = function(x, step) {
  if (is.character(step)) {
    step = as_utf8(step, "...")
    if (S7::S7_inherits(x, loro_map)) {
      return(container_from_ref(loro_map_get_impl(x@ptr, step)))
    }
    if (S7::S7_inherits(x, loro_tree)) {
      if (!grepl("^[0-9]+@[0-9]+$", step) || !loro_tree_contains_impl(x@ptr, step)) {
        return(NULL)
      }
      return(container_from_ref(loro_tree_meta_impl(x@ptr, step)))
    }
    if (is.list(x) && !S7::S7_inherits(x) && step %in% names(x)) {
      return(x[[step]])
    }
    return(NULL)
  }
  if (step < 1) {
    return(NULL)
  }
  if (S7::S7_inherits(x, loro_list)) {
    if (step > loro_list_length_impl(x@ptr)) {
      return(NULL)
    }
    return(container_from_ref(loro_list_get_impl(x@ptr, as.integer(step) - 1L)))
  }
  if (is.list(x) && !S7::S7_inherits(x) && is.null(names(x)) && step <= length(x)) {
    return(x[[step]])
  }
  NULL
}

#' @rdname doc
#' @export
doc_jsonpath = function(doc, path) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  path = check_string(path, "path")
  matches = tryCatch(
    loro_doc_jsonpath_impl(doc@ptr, path),
    error = function(cnd) {
      if (!startsWith(conditionMessage(cnd), "not implemented")) {
        stop(cnd)
      }
      cli::cli_abort(
        c(
          "This JSONPath query uses a feature that Loro does not support.",
          i = "Queries cannot descend into tree containers or use {.code match()} or {.code search()}."
        ),
        call = NULL
      )
    }
  )
  lapply(matches, container_from_ref)
}

#' Synchronize documents
#'
#' @description
#' Replicas exchange state as raw vectors, which can be written to disk
#' or sent over any transport.
#'
#' * `doc_export()` serializes a whole document as a snapshot: its
#'   contents and full history.
#' * `doc_export_updates()` serializes only the changes made since the
#'   version `from`, or the complete history when `from` is `NULL`.
#' * `doc_export_shallow()` serializes a shallow snapshot: the contents
#'   plus only the history after the version `since`. Dropping old
#'   history can make the export much smaller for a document with a
#'   long history, but a document loaded from it cannot check out
#'   versions before `since` or merge edits that branch off before it.
#' * `doc_import()` merges a snapshot or updates into a document.
#'   Importing is commutative and idempotent, so replicas that have seen
#'   the same updates hold the same contents. `bytes` may also be a list
#'   of raw vectors, which are imported together in one step.
#' * `doc_version()` returns the document's current version vector, for
#'   use as the `from` argument of `doc_export_updates()`. See
#'   [`as_version()`].
#' * `doc_is_shallow()` reports whether a document lacks its early
#'   history because it was loaded from a shallow snapshot.
#' * `blob_metadata()` describes an exported raw vector without
#'   importing it.
#' * `doc_export_json()` and `doc_import_json()` exchange changes as
#'   JSON text. This is larger than the binary format but readable, and
#'   useful for inspection and debugging. JSON cannot carry values
#'   nested more than about 120 levels deep: such a document exports,
#'   but the result cannot be imported again. It also cannot carry
#'   containers created with [`map_ensure_container()`], and
#'   `doc_export_json()` refuses to export changes that create one.
#'
#' @section Import status:
#' `doc_import()` and `doc_import_json()` return the document invisibly,
#' so they can be used in a pipe. The outcome of the most recent import
#' into a document is kept with it, and `doc_import_status()` returns
#' it, or `NULL` if nothing has been imported. Like the document, it is
#' shared by every reference to it, so it can be read from the original
#' variable as well as from the result of a pipe. It is a list of two
#' data frames, `success` and `pending`, each with columns `peer`,
#' `start`, and `end` giving a range of that peer's operation counters.
#' `success` holds the operations that were applied. `pending` holds
#' operations that arrived before the changes they depend on; they are
#' kept and applied automatically once the missing changes are
#' imported. A non-empty `pending` means an earlier update was lost or
#' is still in transit.
#'
#' @param doc A [`loro_doc`].
#' @param from A version returned by `doc_version()` to start from,
#'   typically that of the replica the updates are destined for, or
#'   `NULL` for the beginning.
#' @param since A version from [`doc_frontiers()`]. The default, the
#'   latest version, keeps no earlier history at all.
#' @param to A version returned by `doc_version()` to stop at, or `NULL`
#'   for the latest.
#' @param bytes A raw vector produced by one of the export functions,
#'   or for `doc_import()` a list of them.
#' @param json A string produced by `doc_export_json()`.
#'
#' @return `doc_export()`, `doc_export_updates()`, and
#'   `doc_export_shallow()` return a raw vector and `doc_version()` a
#'   version vector.
#'   `doc_import()` and `doc_import_json()` return `doc` invisibly, and
#'   `doc_import_status()` returns an import status or `NULL`; see the
#'   Import status section. `doc_is_shallow()` returns a
#'   logical, `doc_export_json()` a string, and `blob_metadata()` a list
#'   with `mode`, `changes` (the number of changes), `start_timestamp`
#'   and `end_timestamp`, and the versions `start_frontiers`,
#'   `start_version`, and `end_version`.
#'
#' @examples
#' a = loro_doc()
#' text_insert(a, 1, "Hello")
#'
#' b = loro_doc()
#' doc_import(b, doc_export(a))
#'
#' text_insert(a, 6, " world")
#' text_insert(b, 1, ">> ")
#'
#' doc_import(b, doc_export_updates(a, from = doc_version(b)))
#' doc_import(a, doc_export_updates(b, from = doc_version(a)))
#' text_get(a)
#' text_get(b)
#' doc_import_status(b)
#'
#' # Imports return the document, so they can be piped
#' loro_doc() |> doc_import(doc_export(a)) |> text_get()
#'
#' small = doc_export_shallow(a)
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
doc_export = function(doc) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  loro_doc_export_impl(doc@ptr, "snapshot", NULL, NULL)
}

#' @rdname doc_sync
#' @export
doc_export_updates = function(doc, from = NULL) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  if (!is.null(from)) {
    check_version(from, "from")
  }
  loro_doc_export_impl(doc@ptr, "updates", from, NULL)
}

#' @rdname doc_sync
#' @export
doc_export_shallow = function(doc, since = NULL) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  if (!is.null(since)) {
    check_frontiers(since, "since")
  }
  loro_doc_export_impl(doc@ptr, "shallow_snapshot", NULL, since)
}

#' @rdname doc_sync
#' @export
doc_import = function(doc, bytes) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  status = if (is.raw(bytes)) {
    loro_doc_import_impl(doc@ptr, bytes)
  } else if (is.list(bytes) && all(vapply(bytes, is.raw, logical(1)))) {
    loro_doc_import_batch_impl(doc@ptr, bytes)
  } else {
    cli::cli_abort(
      "{.arg bytes} must be a raw vector from an export function, or a list of them."
    )
  }
  doc@state$import_status = import_status(status)
  invisible(doc)
}

#' @rdname doc_sync
#' @export
doc_import_status = function(doc) {
  check_doc(doc)
  doc@state$import_status
}

#' @rdname doc_sync
#' @export
doc_version = function(doc) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  new_version(loro_doc_version_impl(doc@ptr))
}

#' @rdname doc_sync
#' @export
doc_is_shallow = function(doc) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  loro_doc_is_shallow_impl(doc@ptr)
}

#' @rdname doc_sync
#' @export
blob_metadata = function(bytes) {
  if (!is.raw(bytes)) {
    cli::cli_abort("{.arg bytes} must be a raw vector from an export function.")
  }
  meta = loro_blob_metadata_impl(bytes)
  meta$start_frontiers = new_frontiers(meta$start_frontiers)
  meta$start_version = new_version(meta$start_version)
  meta$end_version = new_version(meta$end_version)
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
  on.exit(deliver_events(), add = TRUE)
  for (arg in c("from", "to")) {
    value = get(arg)
    if (!is.null(value)) {
      check_version(value, arg)
    }
  }
  json = loro_doc_export_json_impl(doc@ptr, from, to)
  # Loro 1.18 writes a container created by map_ensure_container() into JSON
  # as an 8-byte binary marker (00 4C 4D 01 ...) in place of a container
  # reference. Importing that JSON stores the marker as a plain value and
  # permanently blocks the key on the receiving replica.
  if (grepl('"value":[0,76,77,1,', json, fixed = TRUE)) {
    cli::cli_abort(
      c(
        "This document cannot be exported as JSON.",
        x = "It has a container created with {.fn map_ensure_container}, which Loro's JSON format does not carry correctly.",
        i = "Use {.fn doc_export} instead."
      )
    )
  }
  json
}

#' @rdname doc_sync
#' @export
doc_import_json = function(doc, json) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  status = loro_doc_import_json_impl(doc@ptr, check_string(json, "json"))
  doc@state$import_status = import_status(status)
  invisible(doc)
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
