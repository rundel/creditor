#' Edit collaborative text
#'
#' @description
#' Positions count Unicode code points and are 1-based, and a range of
#' text is given by the positions of its first and last characters,
#' `start` and `end`, as in [`substr()`]. An empty range has
#' `end = start - 1`.
#'
#' * `text_insert()` inserts `value` before the character currently at
#'   `pos`; `text_push()` appends it to the end.
#' * `text_delete()` removes the characters from `start` to `end`.
#' * `text_replace()` replaces the characters from `start` to `end`
#'   with `value`, as a deletion followed by an insertion.
#' * `text_update()` changes the text to `value` by computing a diff
#'   and applying only the insertions and deletions needed, so
#'   concurrent edits elsewhere in the text, marks, and cursors survive.
#'   With `by = "line"` the diff treats each line as a unit, which is
#'   faster for long texts but replaces a line whole when any part of
#'   it changes.
#' * `text_sub()` returns the characters from `start` to `end`.
#' * `text_get()` returns the current contents as a string, as does
#'   `as.character()`.
#' * `text_length()` returns the number of characters, or the length
#'   in another `unit`. `length()` of a text handle is its number of
#'   characters.
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
#' @param start,end 1-based positions of the first and last characters
#'   of a range. For `text_sub()` they default to the whole text.
#' @param unit,from,to A unit for counting: `"unicode"` (code points,
#'   used everywhere else in this package), `"utf16"` (UTF-16 code
#'   units), or `"utf8"` (bytes).
#' @param by Whether `text_update()` compares the old and new text
#'   character by character (`"char"`) or line by line (`"line"`).
#'
#' @return `text_insert()`, `text_push()`, `text_delete()`,
#'   `text_replace()`, and `text_update()` return `text` invisibly.
#'   `text_sub()` and `text_get()` return a string, and
#'   `text_convert_pos()` and `text_length()` an integer.
#'
#' @examples
#' doc = loro_doc()
#' text = doc_text(doc)
#' text_insert(text, 1, "Hello world")
#' text_push(text, "!")
#' text_sub(text, 1, 5)
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
  check_insert_pos(pos, loro_text_length_impl(text@ptr), "text")
  loro_text_insert_impl(text@ptr, pos - 1L, value)
  invisible(text)
}

#' @rdname text
#' @export
text_push = function(text, value) {
  check_container(text, loro_text, "text")
  value = check_string(value, "value")
  loro_text_insert_impl(text@ptr, loro_text_length_impl(text@ptr), value)
  invisible(text)
}

#' @rdname text
#' @export
text_delete = function(text, start, end) {
  check_container(text, loro_text, "text")
  range = check_range(start, end, loro_text_length_impl(text@ptr), "text")
  loro_text_delete_impl(text@ptr, range$start, range$len)
  invisible(text)
}

#' @rdname text
#' @export
text_update = function(text, value, by = c("char", "line")) {
  check_container(text, loro_text, "text")
  by = rlang::arg_match(by)
  loro_text_update_impl(text@ptr, check_string(value, "value"), by == "line")
  invisible(text)
}

#' @rdname text
#' @export
text_replace = function(text, start, end, value) {
  check_container(text, loro_text, "text")
  value = check_string(value, "value")
  range = check_range(start, end, loro_text_length_impl(text@ptr), "text")
  loro_text_splice_impl(text@ptr, range$start, range$len, value)
  invisible(text)
}

#' @rdname text
#' @export
text_sub = function(text, start = 1, end = text_length(text)) {
  check_container(text, loro_text, "text")
  range = check_range(start, end, loro_text_length_impl(text@ptr), "text")
  loro_text_slice_impl(text@ptr, range$start, range$end)
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
  loro_text_length_unit_impl(text@ptr, rlang::arg_match(unit))
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
  loro_text_convert_pos_impl(text@ptr, pos - 1L, rlang::arg_match(from), rlang::arg_match(to)) + 1L
}

S7::method(length, loro_text) = function(x) loro_text_length_impl(x@ptr)

S7::method(as.character, loro_text) = function(x, ...) loro_container_value_impl(x@ptr, TRUE)
