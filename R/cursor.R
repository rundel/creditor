#' Cursors
#'
#' @description
#' A cursor is a stable reference to a place in a text or list. A plain
#' position goes stale as soon as someone edits earlier in the
#' sequence; a cursor is anchored to a character or element, so it
#' keeps pointing at the same place as the contents change on any
#' replica.
#'
#' * `text_cursor()` creates a cursor at the character currently at
#'   `pos`; `pos = text_length(text) + 1` anchors it to the end of the
#'   text.
#' * `list_cursor()` does the same for the element at `pos` of a list
#'   or movable list.
#' * `cursor_pos()` returns the cursor's current 1-based position in
#'   `doc`. If the anchor character has been deleted, this is the
#'   position where it used to be.
#'
#' One limitation applies to movable lists: a cursor on an element
#' cannot be resolved after that element itself is moved with
#' [`list_move()`], and `cursor_pos()` then raises an error. Moving
#' other elements, or replacing the element with [`list_set()`], is
#' fine.
#'
#' A cursor is a raw vector, so it can be stored or sent to another
#' replica and resolved there, provided that replica has the edit that
#' created the anchor character.
#'
#' @param text A text handle, from [`doc_text()`] or a parent container.
#'   A [`loro_doc`] is also accepted and stands for its default root
#'   container; see [`doc_text()`].
#' @param list A list handle, from [`doc_list()`], [`doc_movable_list()`],
#'   or a parent container.
#'   A [`loro_doc`] is also accepted and stands for its default root
#'   container; see [`doc_text()`].
#' @param pos A 1-based character or element position.
#' @param side Which side of the anchor the cursor sticks to when the
#'   anchor character is deleted: `"middle"` (the default), `"left"`,
#'   or `"right"`.
#' @param doc A [`loro_doc`] holding the container the cursor refers to.
#' @param cursor A raw vector from `text_cursor()` or `list_cursor()`.
#'
#' @return `text_cursor()` and `list_cursor()` return a raw vector and
#'   `cursor_pos()` an integer.
#'
#' @examples
#' doc = loro_doc()
#' text = doc_text(doc)
#' text_insert(text, 1, "world")
#'
#' cursor = text_cursor(text, 1)
#' text_insert(text, 1, "Hello ")
#' cursor_pos(doc, cursor)
#'
#' @name cursor
NULL

#' @rdname cursor
#' @export
text_cursor = function(text, pos, side = c("middle", "left", "right")) {
  ptr = container_ptr(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  side = rlang::arg_match(side)
  length = loro_text_length_impl(ptr)
  if (pos > length + 1L) {
    cli::cli_abort(
      "{.arg pos} must be at most {length + 1L}, one past the end of the text, not {pos}."
    )
  }
  loro_text_cursor_impl(ptr, pos - 1L, c(left = -1L, middle = 0L, right = 1L)[[side]])
}

#' @rdname cursor
#' @export
list_cursor = function(list, pos, side = c("middle", "left", "right")) {
  ptr = container_ptr(list, loro_list, "list")
  pos = check_count(pos, "pos", 1)
  side = rlang::arg_match(side)
  length = loro_list_length_impl(ptr)
  if (pos > length + 1L) {
    cli::cli_abort(
      "{.arg pos} must be at most {length + 1L}, one past the end of the list, not {pos}."
    )
  }
  loro_list_cursor_impl(ptr, pos - 1L, c(left = -1L, middle = 0L, right = 1L)[[side]])
}

#' @rdname cursor
#' @export
cursor_pos = function(doc, cursor) {
  check_doc(doc)
  on.exit(deliver_events(), add = TRUE)
  if (!is.raw(cursor)) {
    cli::cli_abort(
      "{.arg cursor} must be a raw vector from {.fn text_cursor} or {.fn list_cursor}."
    )
  }
  loro_doc_cursor_pos_impl(doc@ptr, cursor) + 1L
}
