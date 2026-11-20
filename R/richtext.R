#' Rich text
#'
#' @description
#' Marks attach a key and value (a style such as `bold = TRUE`, or
#' data such as a link target) to a range of text. They merge across
#' replicas like any other edit. As elsewhere, positions and lengths
#' count Unicode code points and are 1-based.
#'
#' * `text_mark()` marks `len` characters starting at `pos` with
#'   `key = value`.
#' * `text_unmark()` removes the mark `key` from that range.
#' * `text_delta()` returns the text as a list of runs, each a list
#'   with a string `insert` and, for marked runs, a named list
#'   `attributes`. This is the Quill delta format. With `pos` and `len`
#'   it covers only that range.
#' * `text_apply_delta()` edits the text with a list of delta ops.
#'   Each op is a list with exactly one of `retain` (keep that many
#'   characters), `insert` (a string), or `delete` (remove that many
#'   characters); `retain` and `insert` may also carry `attributes`. An
#'   attribute set to `NULL` removes that mark. The output of
#'   `text_delta()` is itself a valid delta.
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
#' @param pos A 1-based character position.
#' @param len Number of characters to mark, unmark, or return. For
#'   `text_delta()`, `pos` and `len` are optional and must be given
#'   together.
#' @param key Name of the mark. It must not contain `":"`.
#' @param value A plain value for the mark; see the Values section of
#'   [`map_set()`].
#' @param delta A list of delta ops.
#' @param doc A [`loro_doc`].
#' @param ... Named strings giving the expand behavior for each key,
#'   for example `comment = "none"`.
#' @param default Expand behavior for keys that are not configured, or
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
#' text_mark(text, 1, 5, "bold")
#' text_mark(text, 7, 5, "link", "https://loro.dev")
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
#' text_mark(text, 1, 5, "author", "cr")
#'
#' @name richtext
NULL

expand_types = c("after", "before", "both", "none")

check_key = function(key, call = sys.call(-1)) {
  key = check_string(key, "key", call = call)
  if (grepl(":", key, fixed = TRUE)) {
    cli::cli_abort("{.arg key} must not contain {.val :}.", call = call)
  }
  key
}

with_style_hint = function(expr, key, call = sys.call(-1)) {
  tryCatch(
    expr,
    error = function(cnd) {
      if (!grepl("Style configuration missing", conditionMessage(cnd), fixed = TRUE)) {
        stop(cnd)
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
text_mark = function(text, pos, len, key, value = TRUE) {
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  len = check_count(len, "len", 1)
  key = check_key(key)
  with_style_hint(loro_text_mark_impl(text@ptr, pos - 1L, pos - 1L + len, key, value), key)
  invisible(text)
}

#' @rdname richtext
#' @export
text_unmark = function(text, pos, len, key) {
  check_container(text, loro_text, "text")
  pos = check_count(pos, "pos", 1)
  len = check_count(len, "len", 1)
  key = check_key(key)
  with_style_hint(loro_text_unmark_impl(text@ptr, pos - 1L, pos - 1L + len, key), key)
  invisible(text)
}

#' @rdname richtext
#' @export
text_delta = function(text, pos = NULL, len = NULL) {
  check_container(text, loro_text, "text")
  if (is.null(pos) && is.null(len)) {
    return(loro_text_delta_impl(text@ptr, NULL, NULL))
  }
  if (is.null(pos) || is.null(len)) {
    cli::cli_abort("{.arg pos} and {.arg len} must be given together.")
  }
  pos = check_count(pos, "pos", 1)
  len = check_count(len, "len", 0)
  loro_text_delta_impl(text@ptr, pos - 1L, pos - 1L + len)
}

#' @rdname richtext
#' @export
text_apply_delta = function(text, delta) {
  check_container(text, loro_text, "text")
  if (!is.list(delta) || is.object(delta)) {
    cli::cli_abort("{.arg delta} must be a list of delta ops.")
  }
  loro_text_apply_delta_impl(text@ptr, delta)
  invisible(text)
}

#' @rdname richtext
#' @export
doc_config_text_style = function(doc, ..., default = NULL) {
  check_doc(doc)
  styles = list(...)
  keys = names(styles)
  if (length(styles) > 0 && (is.null(keys) || any(keys == "") || anyDuplicated(keys) > 0)) {
    cli::cli_abort("Arguments in {.arg ...} must be uniquely named with mark keys.")
  }
  if (any(grepl(":", keys, fixed = TRUE))) {
    cli::cli_abort("Mark keys must not contain {.val :}.")
  }
  is_expand = function(x) is.character(x) && length(x) == 1 && x %in% expand_types
  if (!all(vapply(styles, is_expand, logical(1)))) {
    cli::cli_abort("Each style must be one of {.or {.val {expand_types}}}.")
  }
  if (!is.null(default) && !is_expand(default)) {
    cli::cli_abort("{.arg default} must be {.code NULL} or one of {.or {.val {expand_types}}}.")
  }
  loro_doc_config_text_style_impl(
    doc@ptr,
    as.character(keys),
    as.character(unlist(styles)),
    default
  )
  invisible(doc)
}
