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
#' * `doc_frontiers_to_version()` and `doc_version_to_frontiers()`
#'   convert between the two kinds of version. For example, converting
#'   a row of `doc_changes()` to a version vector lets [`doc_export()`]
#'   produce the updates made since that change.
#' * `doc_compare_frontiers()` orders two versions: `-1` if `from` is an
#'   ancestor of `to`, `1` if it is a descendant, `0` if they are the
#'   same, and `NA` if they are concurrent (neither contains the other).
#' * `doc_changes()` returns one row per change in the history, and
#'   `doc_change()` the one change containing a given operation.
#' * `doc_change_count()` and `doc_op_count()` return the number of
#'   changes and of individual operations in the history.
#' * `doc_changed_containers()` returns the ids of the containers
#'   modified by the given changes.
#' * `doc_checkout()` moves the document to an earlier version, or back
#'   to the latest when `frontiers` is `NULL`. While checked out at an
#'   earlier version the document is detached: it is read-only, and
#'   imported updates are stored but not shown until it returns to the
#'   latest version. `doc_is_detached()` reports this state.
#' * `doc_revert_to()` adds new changes that restore the contents of an
#'   earlier version. History is kept, and the revert synchronizes to
#'   other replicas like any other edit.
#' * `doc_diff()` returns the differences between two versions.
#' * `doc_apply_diff()` takes the changes that `source` made between two
#'   of its versions and applies them to `doc` as new edits. With
#'   `source` left as `doc` this replays or (with the versions swapped)
#'   undoes a span of its own history; with another document it copies
#'   a span of work across without merging the two histories. The
#'   changes are applied by position, so `doc` must hold contents that
#'   match what `source` held at `from`; otherwise the call fails or
#'   lands edits in the wrong place.
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
#' * for a list or movable list (both have type `"list"`), `delta`: ops with `retain` or `delete` counts, or
#'   `insert` holding a list of new elements;
#' * for a map, `updated`: a named list of new values, where `NULL`
#'   marks a deleted key;
#' * for a counter, `increment`: the net amount added;
#' * for a tree, `diff`: a list of node changes, each with `node`, an
#'   `action` (`"create"`, `"move"`, or `"delete"`), and the `parent`
#'   and 1-based `index` it now has and, for moves and deletes, the
#'   `old_parent` and `old_index` it had (`NA` parents are the top
#'   level).
#'
#' Child containers appear by their contents.
#'
#' @param doc A [`loro_doc`].
#' @param frontiers,from,to A version: a raw vector from
#'   `doc_frontiers()` or the `frontiers` column of `doc_changes()`.
#' @param record Whether to record timestamps.
#' @param version A version vector from [`doc_version()`].
#' @param peer,counter The id of an operation: a peer id string and an
#'   operation counter.
#' @param changes A data frame of changes, such as rows of
#'   `doc_changes()`.
#' @param source The [`loro_doc`] whose history `from` and `to` refer
#'   to.
#'
#' @return `doc_frontiers()`, `doc_frontiers_to_version()`, and
#'   `doc_version_to_frontiers()` return raw vectors.
#'   `doc_compare_frontiers()` returns an integer, `doc_change_count()`
#'   and `doc_op_count()` integers, and `doc_changed_containers()` a
#'   character vector. `doc_changes()` and `doc_change()` return a
#'   data frame, `doc_is_detached()` a logical, and `doc_diff()` a named
#'   list. `doc_checkout()`, `doc_revert_to()`,
#'   `doc_apply_diff()`, and `doc_record_timestamps()` return `doc`
#'   invisibly.
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
  changes_frame(loro_doc_changes_impl(doc@ptr))
}

changes_frame = function(changes) {
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

check_peer = function(peer, call = sys.call(-1)) {
  if (!is.character(peer) || length(peer) != 1 || is.na(peer) || !grepl("^[0-9]+$", peer)) {
    cli::cli_abort("{.arg peer} must be a peer id: a string of digits.", call = call)
  }
  peer
}

#' @rdname history
#' @export
doc_change = function(doc, peer, counter) {
  check_doc(doc)
  peer = check_peer(peer)
  counter = check_count(counter, "counter", 0)
  changes_frame(loro_doc_change_impl(doc@ptr, peer, counter))
}

#' @rdname history
#' @export
doc_change_count = function(doc) {
  check_doc(doc)
  loro_doc_counts_impl(doc@ptr)[2]
}

#' @rdname history
#' @export
doc_op_count = function(doc) {
  check_doc(doc)
  loro_doc_counts_impl(doc@ptr)[1]
}

#' @rdname history
#' @export
doc_changed_containers = function(doc, changes) {
  check_doc(doc)
  if (!is.data.frame(changes) || !all(c("peer", "counter", "length") %in% names(changes))) {
    cli::cli_abort(
      "{.arg changes} must be a data frame with columns {.field peer}, {.field counter}, and {.field length}."
    )
  }
  ids = character()
  for (i in seq_len(nrow(changes))) {
    ids = c(ids, loro_doc_changed_containers_impl(
      doc@ptr,
      as.character(changes$peer[i]),
      as.integer(changes$counter[i]),
      as.integer(changes$length[i])
    ))
  }
  sort(unique(ids))
}

#' @rdname history
#' @export
doc_frontiers_to_version = function(doc, frontiers) {
  check_doc(doc)
  check_frontiers(frontiers, "frontiers")
  loro_doc_frontiers_to_version_impl(doc@ptr, frontiers)
}

#' @rdname history
#' @export
doc_version_to_frontiers = function(doc, version) {
  check_doc(doc)
  if (!is.raw(version)) {
    cli::cli_abort("{.arg version} must be a raw vector from {.fn doc_version}.")
  }
  loro_doc_version_to_frontiers_impl(doc@ptr, version)
}

#' @rdname history
#' @export
doc_compare_frontiers = function(doc, from, to) {
  check_doc(doc)
  check_frontiers(from, "from")
  check_frontiers(to, "to")
  loro_doc_compare_frontiers_impl(doc@ptr, from, to)
}

#' @rdname history
#' @export
doc_checkout = function(doc, frontiers = NULL) {
  check_doc(doc)
  if (!is.null(frontiers)) {
    check_frontiers(frontiers, "frontiers")
  }
  loro_doc_checkout_impl(doc@ptr, frontiers)
  deliver_events()
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
  deliver_events()
  invisible(doc)
}

#' @rdname history
#' @export
doc_diff = function(doc, from, to) {
  check_doc(doc)
  check_frontiers(from, "from")
  check_frontiers(to, "to")
  diff = loro_doc_diff_impl(doc@ptr, from, to)
  deliver_events()
  diff
}

#' @rdname history
#' @export
doc_apply_diff = function(doc, from, to, source = doc) {
  check_doc(doc)
  if (!S7::S7_inherits(source, loro_doc)) {
    cli::cli_abort("{.arg source} must be a {.cls loro_doc}.")
  }
  check_frontiers(from, "from")
  check_frontiers(to, "to")
  loro_doc_apply_diff_impl(doc@ptr, source@ptr, from, to)
  deliver_events()
  invisible(doc)
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
