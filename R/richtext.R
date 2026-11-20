#' Rich text
#'
#' @description
#' Marks attach a key and value (a style such as `bold = TRUE`, or
#' data such as a link target) to a range of text. They merge across
#' replicas like any other edit. As elsewhere, positions count Unicode
#' code points and are 1-based, and a range runs from `start` to `end`.
#'
#' * `text_mark()` marks the characters from `start` to `end` with the
#'   marks given as `key = value` arguments.
#' * `text_unmark()` removes the marks named in `keys` from that range.
#' * `text_delta()` returns the text as a list of runs, each a list
#'   with a string `insert` and, for marked runs, a named list
#'   `attributes`. This is the Quill delta format. With `start` and
#'   `end` it covers only that range.
#' * `text_apply_delta()` edits the text with a list of delta ops.
#'   Each op is a list with exactly one of `retain` (keep that many
#'   characters), `insert` (a string), or `delete` (remove that many
#'   characters); `retain` and `insert` may also carry `attributes`. An
#'   attribute set to `NULL` removes that mark. The output of
#'   `text_delta()` is itself a valid delta. A delta that reaches past
#'   the end of the text is rejected before anything is applied, but if
#'   an op fails for another reason (such as an unconfigured mark key)
#'   the ops before it stay applied.
#' * `doc_config_text_style()` declares mark keys and how each behaves
#'   when text is inserted at the edge of a marked range.
#'
#' @section Style configuration:
#' A key must be configured before it can be used in a mark. New
#' documents know these keys: `bold`, `italic`, and `underline` (which
#' expand `"after"`), and `link`, `highlight`, `comment`, and `code`
#' (which expand `"none"`).
#'
#' The expand behavior decides whether text inserted at a boundary of a
#' marked range joins the mark: `"after"` for text inserted at its end,
#' `"before"` at its start, `"both"`, or `"none"`.
#'
#' Each call to `doc_config_text_style()` sets the complete
#' configuration: the built-in keys, overridden or extended by the keys
#' given in `...`. The configuration is local to a replica and is not
#' synchronized, so every replica should configure a key the same way.
#'
#' @param text A text handle, from [`doc_text()`] or a parent container.
#'   A [`loro_doc`] is also accepted and stands for its default root
#'   container; see [`doc_text()`].
#' @param start,end 1-based positions of the first and last characters
#'   of the range. For `text_delta()` they default to the whole text.
#' @param ... For `text_mark()`, the marks to apply, each a plain value
#'   (see the Values section of [`map_set()`]) named with its key, for
#'   example `bold = TRUE` or `link = "https://loro.dev"`. A key must
#'   not contain `":"`, and a value of `NULL` or `NA` removes the mark,
#'   as `text_unmark()` does. For `doc_config_text_style()`, strings
#'   giving the expand behavior of each key, for example
#'   `comment = "none"`. Both are [dynamic dots][rlang::dyn-dots].
#' @param keys A character vector of mark names.
#' @param delta A list of delta ops.
#' @param doc A [`loro_doc`].
#' @param .default Expand behavior for keys that are not configured, or
#'   `NULL` to reject them.
#'
#' @return `text_mark()`, `text_unmark()`, and `text_apply_delta()`
#'   return `text` invisibly; `text_delta()` returns a list; and
#'   `doc_config_text_style()` returns `doc` invisibly.
#'
#' @examples
#' doc = loro_doc()
#' text = doc_text(doc)
#' text_insert(text, 1, "Hello world")
#' text_mark(text, 1, 5, bold = TRUE)
#' text_mark(text, 7, 11, link = "https://loro.dev", italic = TRUE)
#' text_unmark(text, 7, 11, "italic")
#' str(text_delta(text))
#'
#' text_apply_delta(text, list(
#'   list(retain = 5),
#'   list(insert = ",", attributes = list(bold = TRUE)),
#'   list(delete = 1)
#' ))
#' text_get(text)
#'
#' doc_config_text_style(doc, author = "none")
#' text_mark(text, 1, 5, author = "cr")
#'
#' @name richtext
NULL

expand_types = c("after", "before", "both", "none")

check_mark_keys = function(keys, call = rlang::caller_env()) {
  if (any(grepl(":", keys, fixed = TRUE))) {
    cli::cli_abort("Mark keys must not contain {.val :}.", call = call)
  }
  keys
}

check_mark_range = function(start, end, size, call = rlang::caller_env()) {
  range = check_range(start, end, size, "text", call = call)
  if (range$len == 0L) {
    cli::cli_abort("{.arg start} and {.arg end} must cover at least one character.", call = call)
  }
  range
}

with_style_hint = function(expr, key = NULL, call = rlang::caller_env()) {
  tryCatch(
    expr,
    error = function(cnd) {
      message = conditionMessage(cnd)
      if (!grepl("Style configuration missing", message, fixed = TRUE)) {
        stop(cnd)
      }
      if (is.null(key)) {
        found = regmatches(message, regexec('InternalString\\("([^"]*)"\\)', message))[[1]]
        key = if (length(found) == 2) found[2] else "?"
      }
      cli::cli_abort(
        c(
          "The mark key {.val {key}} is not configured for this document.",
          i = "Declare it with {.fn doc_config_text_style}."
        ),
        call = call
      )
    }
  )
}

#' @rdname richtext
#' @export
text_mark = function(text, start, end, ...) {
  ptr = container_ptr(text, loro_text, "text")
  marks = named_values(..., .what = "a mark key")
  check_mark_keys(names(marks))
  range = check_mark_range(start, end, loro_text_length_impl(ptr))
  for (key in names(marks)) {
    with_style_hint(
      loro_text_mark_impl(ptr, range$start, range$end, key, marks[[key]]),
      key
    )
  }
  invisible(text)
}

#' @rdname richtext
#' @export
text_unmark = function(text, start, end, keys) {
  ptr = container_ptr(text, loro_text, "text")
  keys = check_mark_keys(check_strings(keys, "keys"))
  range = check_mark_range(start, end, loro_text_length_impl(ptr))
  for (key in keys) {
    with_style_hint(loro_text_unmark_impl(ptr, range$start, range$end, key), key)
  }
  invisible(text)
}

#' @rdname richtext
#' @export
text_delta = function(text, start = 1, end = text_length(text)) {
  ptr = container_ptr(text, loro_text, "text")
  size = loro_text_length_impl(ptr)
  range = check_range(start, end, size, "text")
  if (range$len == size) {
    return(loro_text_delta_impl(ptr, NULL, NULL))
  }
  loro_text_delta_impl(ptr, range$start, range$end)
}

#' @rdname richtext
#' @export
text_apply_delta = function(text, delta) {
  ptr = container_ptr(text, loro_text, "text")
  if (!is.list(delta) || is.object(delta)) {
    cli::cli_abort("{.arg delta} must be a list of delta ops.")
  }
  with_style_hint(loro_text_apply_delta_impl(ptr, delta))
  invisible(text)
}

#' @rdname richtext
#' @export
doc_config_text_style = function(doc, ..., .default = NULL) {
  check_doc(doc)
  styles = named_values(..., .what = "a mark key")
  keys = check_mark_keys(names(styles))
  is_expand = function(x) is.character(x) && length(x) == 1 && x %in% expand_types
  if (!all(vapply(styles, is_expand, logical(1)))) {
    cli::cli_abort("Each style must be one of {.or {.val {expand_types}}}.")
  }
  if (!is.null(.default) && !is_expand(.default)) {
    cli::cli_abort("{.arg .default} must be {.code NULL} or one of {.or {.val {expand_types}}}.")
  }
  loro_doc_config_text_style_impl(
    doc@ptr,
    as.character(keys),
    as.character(unlist(styles)),
    .default
  )
  invisible(doc)
}
