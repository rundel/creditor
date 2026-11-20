#' Document history
#'
#' @description
#' A document keeps its full editing history, so earlier versions can be
#' inspected, compared, and restored.
#'
#' * `doc_frontiers()` returns the version the document is currently
#'   showing, as a raw vector. Unlike the version vector from
#'   [`doc_version()`], which is meant for synchronization, frontiers
#'   are a compact name for one point in history.
#' * `doc_changes()` returns one row per change in the history.
#' * `doc_checkout()` moves the document to an earlier version, or back
#'   to the latest when `frontiers` is `NULL`. While checked out at an
#'   earlier version the document is detached: it is read-only, and
#'   imported updates are stored but not shown until it returns to the
#'   latest version. `doc_is_detached()` reports this state.
#' * `doc_revert_to()` adds new changes that restore the contents of an
#'   earlier version. History is kept, and the revert synchronizes to
#'   other replicas like any other edit.
#' * `doc_diff()` returns the differences between two versions.
#' * `doc_record_timestamps()` turns on recording of the wall-clock
#'   time of each new change. It is off by default.
#'
#' @section Changes:
#' `doc_changes()` returns a data frame, in causal order, with columns:
#'
#' * `peer`, `counter`: the id of the change's first operation.
#' * `lamport`: its logical timestamp.
#' * `length`: the number of operations in the change.
#' * `timestamp`: when it was committed (`NA` if not recorded).
#' * `message`: the commit message (`NA` if none).
#' * `frontiers`: a list column holding the version just after the
#'   change, suitable for `doc_checkout()`, `doc_revert_to()`,
#'   `doc_diff()`, and `doc_fork()`.
#'
#' Consecutive commits by one peer that carry no message may be stored
#' as a single change, so rows do not correspond one-to-one with calls
#' to [`doc_commit()`].
#'
#' @section Diffs:
#' `doc_diff()` returns a named list with one element per changed
#' container, named by container id (see [`container_id()`]). Each
#' element has a `type` and:
#'
#' * for text, `delta`: delta ops as in [`text_apply_delta()`];
#' * for a list, `delta`: ops with `retain` or `delete` counts, or
#'   `insert` holding a list of new elements;
#' * for a map, `updated`: a named list of new values, where `NULL`
#'   marks a deleted key.
#'
#' Child containers appear by their contents.
#'
#' @param doc A [`loro_doc`].
#' @param frontiers,from,to A version: a raw vector from
#'   `doc_frontiers()` or the `frontiers` column of `doc_changes()`.
#' @param record Whether to record timestamps.
#'
#' @return `doc_frontiers()` returns a raw vector, `doc_changes()` a
#'   data frame, `doc_is_detached()` a logical, and `doc_diff()` a named
#'   list. `doc_checkout()`, `doc_revert_to()`, and
#'   `doc_record_timestamps()` return `doc` invisibly.
#'
#' @examples
#' doc = loro_doc()
#' text = doc_text(doc)
#'
#' text_insert(text, 1, "Hello")
#' doc_commit(doc, "greeting")
#' v1 = doc_frontiers(doc)
#'
#' text_insert(text, 6, " world")
#' doc_commit(doc, "audience")
#' v2 = doc_frontiers(doc)
#'
#' doc_changes(doc)[, c("lamport", "length", "message")]
#' str(doc_diff(doc, v1, v2))
#'
#' doc_checkout(doc, v1)
#' text_get(text)
#' doc_checkout(doc)
#'
#' doc_revert_to(doc, v1)
#' text_get(text)
#'
#' @name history
NULL

check_frontiers = function(x, arg, call = sys.call(-1)) {
  if (!is.raw(x)) {
    cli::cli_abort(
      "{.arg {arg}} must be a raw vector from {.fn doc_frontiers} or {.fn doc_changes}.",
      call = call
    )
  }
  invisible(x)
}

#' @rdname history
#' @export
doc_frontiers = function(doc) {
  check_doc(doc)
  loro_doc_frontiers_impl(doc@ptr)
}

#' @rdname history
#' @export
doc_changes = function(doc) {
  check_doc(doc)
  changes = loro_doc_changes_impl(doc@ptr)
  timestamp = changes$timestamp
  timestamp[timestamp == 0] = NA
  out = data.frame(
    peer = changes$peer,
    counter = changes$counter,
    lamport = changes$lamport,
    length = changes$length,
    timestamp = as.POSIXct(timestamp, origin = "1970-01-01", tz = "UTC"),
    message = changes$message
  )
  out$frontiers = changes$frontiers
  out
}

#' @rdname history
#' @export
doc_checkout = function(doc, frontiers = NULL) {
  check_doc(doc)
  if (!is.null(frontiers)) {
    check_frontiers(frontiers, "frontiers")
  }
  loro_doc_checkout_impl(doc@ptr, frontiers)
  invisible(doc)
}

#' @rdname history
#' @export
doc_is_detached = function(doc) {
  check_doc(doc)
  loro_doc_is_detached_impl(doc@ptr)
}

#' @rdname history
#' @export
doc_revert_to = function(doc, frontiers) {
  check_doc(doc)
  check_frontiers(frontiers, "frontiers")
  loro_doc_revert_to_impl(doc@ptr, frontiers)
  invisible(doc)
}

#' @rdname history
#' @export
doc_diff = function(doc, from, to) {
  check_doc(doc)
  check_frontiers(from, "from")
  check_frontiers(to, "to")
  lapply(loro_doc_diff_impl(doc@ptr, from, to), function(diff) {
    names(diff)[names(diff) == "type_"] = "type"
    diff
  })
}

#' @rdname history
#' @export
doc_record_timestamps = function(doc, record = TRUE) {
  check_doc(doc)
  if (!is.logical(record) || length(record) != 1 || is.na(record)) {
    cli::cli_abort("{.arg record} must be {.code TRUE} or {.code FALSE}.")
  }
  loro_doc_record_timestamps_impl(doc@ptr, record)
  invisible(doc)
}
