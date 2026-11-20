#' Undo and redo
#'
#' @description
#' An undo manager tracks the local changes made to a document after it
#' is created, and can undo and redo them. Changes imported from other
#' replicas are never undone: an undo reverses only this replica's own
#' edits, adjusted for whatever others have done since.
#'
#' * `doc_undo_manager()` creates an undo manager for `doc`.
#' * `undo()` and `redo()` step backward and forward. They return `TRUE`
#'   if the document changed.
#' * `can_undo()` and `can_redo()` report whether a step is available.
#' * `undo_group()` evaluates `code` and records all the changes it
#'   makes as a single undo step.
#'
#' Each commit is one undo step, so call [`doc_commit()`] between edits
#' that should be undone separately. Commits closer together than
#' `merge_interval` are combined into one step.
#'
#' @param doc A [`loro_doc`].
#' @param merge_interval Commits made within this many milliseconds of
#'   the previous one join its undo step. The default, `0`, keeps every
#'   commit separate.
#' @param max_steps Maximum number of undo steps to keep.
#' @param manager An undo manager from `doc_undo_manager()`.
#' @param code Code that edits the document.
#'
#' @return `doc_undo_manager()` returns an undo manager. `undo()`,
#'   `redo()`, `can_undo()`, and `can_redo()` return a logical.
#'   `undo_group()` returns the value of `code`.
#'
#' @examples
#' doc = loro_doc()
#' text = doc_text(doc)
#' manager = doc_undo_manager(doc)
#'
#' text_insert(text, 1, "Hello")
#' doc_commit(doc)
#' text_insert(text, 6, " world")
#' doc_commit(doc)
#'
#' undo(manager)
#' text_get(text)
#' redo(manager)
#' text_get(text)
#'
#' @name undo
NULL

loro_undo_manager = S7::new_class(
  "loro_undo_manager",
  package = "creditor",
  properties = list(ptr = S7::class_any)
)

check_manager = function(manager, call = sys.call(-1)) {
  if (!S7::S7_inherits(manager, loro_undo_manager)) {
    cli::cli_abort(
      "{.arg manager} must be a {.cls loro_undo_manager}, not {.obj_type_friendly {manager}}.",
      call = call
    )
  }
  invisible(manager)
}

#' @rdname undo
#' @export
doc_undo_manager = function(doc, merge_interval = 0, max_steps = 100) {
  check_doc(doc)
  merge_interval = check_count(merge_interval, "merge_interval", 0)
  max_steps = check_count(max_steps, "max_steps", 1)
  loro_undo_manager(ptr = loro_undo_new_impl(doc@ptr, as.numeric(merge_interval), max_steps))
}

#' @rdname undo
#' @export
undo = function(manager) {
  check_manager(manager)
  changed = loro_undo_undo_impl(manager@ptr)
  deliver_events()
  changed
}

#' @rdname undo
#' @export
redo = function(manager) {
  check_manager(manager)
  changed = loro_undo_redo_impl(manager@ptr)
  deliver_events()
  changed
}

#' @rdname undo
#' @export
can_undo = function(manager) {
  check_manager(manager)
  loro_undo_counts_impl(manager@ptr)[1] > 0L
}

#' @rdname undo
#' @export
can_redo = function(manager) {
  check_manager(manager)
  loro_undo_counts_impl(manager@ptr)[2] > 0L
}

#' @rdname undo
#' @export
undo_group = function(manager, code) {
  check_manager(manager)
  loro_undo_group_impl(manager@ptr, TRUE)
  on.exit({
    loro_undo_group_impl(manager@ptr, FALSE)
    deliver_events()
  })
  code
}

S7::method(print, loro_undo_manager) = function(x, ...) {
  counts = loro_undo_counts_impl(x@ptr)
  cli::cli_text("{.cls loro_undo_manager} {counts[1]} undo, {counts[2]} redo")
  invisible(x)
}
