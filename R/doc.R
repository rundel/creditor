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
#'   [`doc_changes()`]. Edits are also committed implicitly on export,
#'   import, and checkout.
#' * `doc_value()` returns the whole document as a named list with one
#'   element per root container.
#'
#' @param doc A [`loro_doc`].
#' @param at A version from [`doc_frontiers()`] to fork at, or `NULL`
#'   for the current version.
#' @param message A string describing the change, or `NULL`.
#'
#' @return `doc_peer_id()` returns a string, `doc_fork()` a new
#'   `loro_doc`, `doc_commit()` returns `doc` invisibly, and
#'   `doc_value()` a named list.
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
doc_commit = function(doc, message = NULL) {
  check_doc(doc)
  if (!is.null(message)) {
    message = check_string(message, "message")
  }
  loro_doc_commit_impl(doc@ptr, message)
  deliver_events()
  invisible(doc)
}

#' @rdname doc
#' @export
doc_value = function(doc) {
  check_doc(doc)
  loro_doc_value_impl(doc@ptr)
}

#' Synchronize documents
#'
#' @description
#' Replicas exchange state as raw vectors, which can be written to disk
#' or sent over any transport.
#'
#' * `doc_export()` serializes a document, either as a full `"snapshot"`
#'   or as `"updates"`: the changes made since the version `from`, or
#'   the complete history when `from` is `NULL`.
#' * `doc_import()` merges a snapshot or updates into a document.
#'   Importing is commutative and idempotent, so replicas that have seen
#'   the same updates hold the same contents.
#' * `doc_version()` returns the document's current version (an encoded
#'   version vector) for use as the `from` argument of a later export.
#'
#' @param doc A [`loro_doc`].
#' @param mode Either `"snapshot"` or `"updates"`.
#' @param from A version returned by `doc_version()`, typically that of
#'   the replica the updates are destined for. Only used when `mode` is
#'   `"updates"`.
#' @param bytes A raw vector produced by `doc_export()`.
#'
#' @return `doc_export()` and `doc_version()` return raw vectors;
#'   `doc_import()` returns `doc` invisibly.
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
#' @name doc_sync
NULL

#' @rdname doc_sync
#' @export
doc_export = function(doc, mode = c("snapshot", "updates"), from = NULL) {
  check_doc(doc)
  mode = match.arg(mode)
  if (!is.null(from) && !is.raw(from)) {
    cli::cli_abort("{.arg from} must be a raw vector from {.fn doc_version} or {.code NULL}.")
  }
  bytes = loro_doc_export_impl(doc@ptr, mode, from)
  deliver_events()
  bytes
}

#' @rdname doc_sync
#' @export
doc_import = function(doc, bytes) {
  check_doc(doc)
  if (!is.raw(bytes)) {
    cli::cli_abort("{.arg bytes} must be a raw vector from {.fn doc_export}.")
  }
  loro_doc_import_impl(doc@ptr, bytes)
  deliver_events()
  invisible(doc)
}

#' @rdname doc_sync
#' @export
doc_version = function(doc) {
  check_doc(doc)
  loro_doc_version_impl(doc@ptr)
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
