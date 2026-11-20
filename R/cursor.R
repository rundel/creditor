#' Cursors
#'
#' @description
#' A cursor is a stable reference to a place in a text. A plain
#' position goes stale as soon as someone edits earlier in the text; a
#' cursor is anchored to a character, so it keeps pointing at the same
#' place as the text changes on any replica.
#'
#' * `text_cursor()` creates a cursor at the character currently at
#'   `pos`; `pos = text_length(text) + 1` anchors it to the end of the
#'   text.
#' * `cursor_pos()` returns the cursor's current 1-based position in
#'   `doc`. If the anchor character has been deleted, this is the
#'   position where it used to be.
#'
#' A cursor is a raw vector, so it can be stored or sent to another
#' replica and resolved there, provided that replica has the edit that
#' created the anchor character.
#'
#' @param text A text handle, from [`doc_text()`] or a parent container.
#' @param pos A 1-based character position.
#' @param side Which side of the anchor the cursor sticks to when the
#'   anchor character is deleted: `"middle"` (the default), `"left"`,
#'   or `"right"`.
#' @param doc A [`loro_doc`] holding the text the cursor refers to.
#' @param cursor A raw vector from `text_cursor()`.
#'
#' @return `text_cursor()` returns a raw vector and `cursor_pos()` an
#'   integer.
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
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  side = match.arg(side)
  length = loro_text_length_impl(text@ptr)
  if (pos > length + 1L) {
    cli::cli_abort(
      "{.arg pos} must be at most {length + 1L}, one past the end of the text, not {pos}."
    )
  }
  loro_text_cursor_impl(text@ptr, pos - 1L, c(left = -1L, middle = 0L, right = 1L)[[side]])
}

#' @rdname cursor
#' @export
cursor_pos = function(doc, cursor) {
  check_doc(doc)
  if (!is.raw(cursor)) {
    cli::cli_abort("{.arg cursor} must be a raw vector from {.fn text_cursor}.")
  }
  loro_doc_cursor_pos_impl(doc@ptr, cursor) + 1L
}
