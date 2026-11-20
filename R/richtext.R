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
#'   `end` it covers only that range. The list has class `loro_delta`,
#'   which prints as Markdown (see `text_markdown()`) and keeps the
#'   plain list structure for [`str()`][utils::str] and indexing. Its
#'   `print()` and `format()` methods take a `format` argument, one of
#'   `"markdown"`, `"html"`, `"ansi"`, or `"list"` (the [`str()`][utils::str]
#'   view), whose default comes from the `creditor.delta_format` option,
#'   so `options(creditor.delta_format = "ansi")` changes how deltas
#'   autoprint. Printing never warns: when the chosen format leaves
#'   marks out, a note at the end names them.
#' * `text_markdown()` and `text_html()` render the text with its marks
#'   as a Markdown or HTML string. Both handle `bold`, `italic`,
#'   `underline`, `code`, and `link` (whose value is the target URL);
#'   Markdown writes underline as `<u>` tags. HTML also writes
#'   `highlight` as `<mark>` and any other mark as a `<span>` with a
#'   `data-` attribute holding its value, for example
#'   `<span data-comment="check this">`. Markdown cannot express the
#'   other marks, so `text_markdown()` leaves them out with a warning.
#' * `text_ansi()` renders the text for the console with ANSI styles
#'   from cli: bold, italic, and underline as themselves, `code` in
#'   cyan, `highlight` on a yellow background, and `link` in blue as a
#'   hyperlink where the terminal supports one. Other marks have no
#'   style and are left out with a warning. Styles appear only where cli detects color support (see
#'   [cli::num_ansi_colors()]); elsewhere the result is the plain text.
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
#'   of the range. For `text_delta()` and the rendering functions they
#'   default to the whole text.
#' @param .text,.start,.end The text handle and range for `text_mark()`,
#'   as for `text`, `start`, and `end`. The argument names start with a
#'   dot so that they cannot clash with a mark key given in `...`.
#' @param ... For `text_mark()`, the marks to apply, each a plain value
#'   (see the Values section of [`map_set()`]) named with its key, for
#'   example `bold = TRUE` or `link = "https://loro.dev"`. A key must
#'   not contain `":"`, and a value of `NULL` or `NA` removes the mark,
#'   as `text_unmark()` does. For `doc_config_text_style()`, strings
#'   giving the expand behavior of each key, for example
#'   `comment = "none"`. Both are [dynamic dots][rlang::dyn-dots].
#' @param marks How to render marks, overriding the defaults or covering
#'   marks the format cannot otherwise show: `NULL`, or a list named by
#'   mark key. For `text_markdown()` and `text_html()`, each entry is a
#'   character vector of two strings, the text written before and after
#'   the marked range (`bold = c(before = "__", after = "__")`; the names
#'   are optional), or a function that takes the mark's value and returns
#'   them (`author = \(value) c(before = "<cite>", after = paste0(" (",
#'   value, ")</cite>"))`). The mark's range decides where they are
#'   written.
#'   They are written as given, without escaping, so a function that puts
#'   the value into HTML should escape it. For `text_ansi()`, each entry
#'   is a function that takes the text and returns it styled, such as
#'   [cli::col_magenta()]; a function with an argument named `value` is
#'   also given the mark's value. A mark with an entry is never left out.
#' @param strict For `text_markdown()` and `text_ansi()`, whether
#'   leaving out a mark the format cannot show is an error rather than a
#'   warning. Both conditions have class `creditor_dropped_marks`, so
#'   the warning can be silenced on its own with
#'   [`suppressWarnings(classes = "creditor_dropped_marks")`][base::suppressWarnings].
#' @param keys A character vector of mark names.
#' @param delta A list of delta ops.
#' @param .doc A [`loro_doc`]. The argument name starts with a dot so
#'   that it cannot clash with a mark key given in `...`.
#' @param .default Expand behavior for keys that are not configured, or
#'   `NULL` to reject them.
#'
#' @return `text_mark()` returns `.text` invisibly, `text_unmark()` and
#'   `text_apply_delta()` return `text` invisibly, `text_delta()` returns
#'   a `loro_delta` list, `text_markdown()` and `text_html()` return a
#'   string, `text_ansi()` returns a [cli::ansi_string()], and `doc_config_text_style()` returns `.doc` invisibly.
#'
#' @examples
#' doc = loro_doc()
#' text = doc_text(doc)
#' text_insert(text, 1, "Hello world")
#' text_mark(text, 1, 5, bold = TRUE)
#' text_mark(text, 7, 11, link = "https://loro.dev", italic = TRUE)
#' text_unmark(text, 7, 11, "italic")
#' text_delta(text)
#' print(text_delta(text), format = "html")
#' str(text_delta(text))
#' text_markdown(text)
#' text_html(text)
#' text_markdown(text, marks = list(bold = c(before = "__", after = "__")))
#' cat(text_ansi(text), "\n")
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

check_mark_range = function(
  start,
  end,
  size,
  args = c("start", "end"),
  call = rlang::caller_env()
) {
  range = check_range(start, end, size, "text", args = args, call = call)
  if (range$len == 0L) {
    cli::cli_abort("{.arg {args[1]}} and {.arg {args[2]}} must cover at least one character.", call = call)
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
text_mark = function(.text, .start, .end, ...) {
  ptr = container_ptr(.text, loro_text, ".text")
  marks = named_values(..., .what = "a mark key")
  check_mark_keys(names(marks))
  range = check_mark_range(.start, .end, loro_text_length_impl(ptr), args = c(".start", ".end"))
  for (key in names(marks)) {
    with_style_hint(
      loro_text_mark_impl(ptr, range$start, range$end, key, marks[[key]]),
      key
    )
  }
  invisible(.text)
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
  delta = if (range$len == size) {
    loro_text_delta_impl(ptr, NULL, NULL)
  } else {
    loro_text_delta_impl(ptr, range$start, range$end)
  }
  structure(delta, class = "loro_delta")
}

#' @rdname richtext
#' @export
text_markdown = function(text, start = 1, end = text_length(text), marks = NULL, strict = FALSE) {
  check_bool(strict, "strict")
  marks = check_renderers(marks, "delims")
  delta = text_delta(text, start, end)
  check_dropped_marks(delta, markdown_marks, "text_markdown", strict, marks)
  delta_markdown(delta, marks)
}

#' @rdname richtext
#' @export
text_ansi = function(text, start = 1, end = text_length(text), marks = NULL, strict = FALSE) {
  check_bool(strict, "strict")
  marks = check_renderers(marks, "style")
  delta = text_delta(text, start, end)
  check_dropped_marks(delta, ansi_marks, "text_ansi", strict, marks)
  delta_ansi(delta, marks)
}

#' @rdname richtext
#' @export
text_html = function(text, start = 1, end = text_length(text), marks = NULL) {
  marks = check_renderers(marks, "delims")
  delta_html(text_delta(text, start, end), marks)
}

#' @rdname richtext
#' @export
text_apply_delta = function(text, delta) {
  ptr = container_ptr(text, loro_text, "text")
  if (inherits(delta, "loro_delta")) {
    delta = unclass(delta)
  }
  if (!is.list(delta) || is.object(delta)) {
    cli::cli_abort("{.arg delta} must be a list of delta ops.")
  }
  with_style_hint(loro_text_apply_delta_impl(ptr, delta))
  invisible(text)
}

#' @rdname richtext
#' @export
doc_config_text_style = function(.doc, ..., .default = NULL) {
  check_doc(.doc, ".doc")
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
    .doc@ptr,
    as.character(keys),
    as.character(unlist(styles)),
    .default
  )
  invisible(.doc)
}
