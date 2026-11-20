#' Edit collaborative text
#'
#' @description
#' Positions and lengths count Unicode code points and are 1-based,
#' matching [`substr()`].
#'
#' * `text_insert()` inserts `value` before the character currently at
#'   `pos`; `pos = text_length(text) + 1` appends.
#' * `text_delete()` removes `len` characters starting at `pos`.
#' * `text_splice()` replaces `len` characters starting at `pos` with
#'   `value`, as a deletion followed by an insertion.
#' * `text_update()` changes the text to `value` by computing a diff
#'   and applying only the insertions and deletions needed, so
#'   concurrent edits elsewhere in the text, marks, and cursors survive.
#'   With `by = "line"` the diff treats each line as a unit, which is
#'   faster for long texts but replaces a line whole when any part of
#'   it changes.
#' * `text_slice()` returns `len` characters starting at `pos`.
#' * `text_get()` returns the current contents as a string.
#' * `text_length()` returns the number of characters, or the length
#'   in another `unit`.
#' * `text_convert_pos()` converts a position between units, for
#'   exchanging positions with software that counts differently:
#'   JavaScript, and so browser-based editors, counts UTF-16 code
#'   units, in which a character outside the basic plane (most emoji)
#'   counts as two. Positions stay 1-based in every unit, so subtract 1
#'   to get a 0-based JavaScript offset. A position in the middle of a
#'   character converts to the position of that character, and the
#'   result is `NA` if `pos` is out of range.
#'
#' @param text A text handle, from [`doc_text()`] or a parent container.
#' @param pos A 1-based character position.
#' @param value A string: the text to insert, or the new contents for
#'   `text_update()`.
#' @param len Number of characters to delete, replace, or return.
#' @param unit,from,to A unit for counting: `"unicode"` (code points,
#'   used everywhere else in this package), `"utf16"` (UTF-16 code
#'   units), or `"utf8"` (bytes).
#' @param by Whether `text_update()` compares the old and new text
#'   character by character (`"char"`) or line by line (`"line"`).
#'
#' @return `text_insert()`, `text_delete()`, `text_splice()`, and
#'   `text_update()` return `text` invisibly, `text_slice()` a string, `text_convert_pos()` an integer,
#'   `text_get()` a string, and `text_length()` an integer.
#'
#' @examples
#' doc = loro_doc()
#' text = doc_text(doc)
#' text_insert(text, 1, "Hello world")
#' text_delete(text, 1, 6)
#' text_get(text)
#' text_length(text)
#'
#' text_update(text, "brave new world")
#' text_get(text)
#'
#' @name text
NULL

#' @rdname text
#' @export
text_insert = function(text, pos, value) {
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  value = check_string(value, "value")
  loro_text_insert_impl(text@ptr, pos - 1L, value)
  invisible(text)
}

#' @rdname text
#' @export
text_delete = function(text, pos, len) {
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  len = check_count(len, "len", 0)
  loro_text_delete_impl(text@ptr, pos - 1L, len)
  invisible(text)
}

#' @rdname text
#' @export
text_update = function(text, value, by = c("char", "line")) {
  check_container(text, loro_text, "text")
  by = match.arg(by)
  loro_text_update_impl(text@ptr, check_string(value, "value"), by == "line")
  invisible(text)
}

#' @rdname text
#' @export
text_splice = function(text, pos, len, value) {
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  len = check_count(len, "len", 0)
  loro_text_splice_impl(text@ptr, pos - 1L, len, check_string(value, "value"))
  invisible(text)
}

#' @rdname text
#' @export
text_slice = function(text, pos, len) {
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  len = check_count(len, "len", 0)
  loro_text_slice_impl(text@ptr, pos - 1L, pos - 1L + len)
}

#' @rdname text
#' @export
text_get = function(text) {
  check_container(text, loro_text, "text")
  loro_container_value_impl(text@ptr, TRUE)
}

#' @rdname text
#' @export
text_length = function(text, unit = c("unicode", "utf16", "utf8")) {
  check_container(text, loro_text, "text")
  loro_text_length_unit_impl(text@ptr, match.arg(unit))
}

#' @rdname text
#' @export
text_convert_pos = function(
  text,
  pos,
  from = c("unicode", "utf16", "utf8"),
  to = c("utf16", "unicode", "utf8")
) {
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  loro_text_convert_pos_impl(text@ptr, pos - 1L, match.arg(from), match.arg(to)) + 1L
}
