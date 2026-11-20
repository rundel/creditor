mark_order = c("link", "underline", "highlight", "bold", "italic", "code")

mark_is_on = function(value) {
  !is.null(value) && !identical(value, FALSE) && !identical(value, NA)
}

run_marks = function(attributes) {
  attributes = Filter(mark_is_on, attributes)
  keys = names(attributes)
  attributes[c(intersect(mark_order, keys), sort(setdiff(keys, mark_order)))]
}

delta_runs = function(delta) {
  Filter(function(op) is.character(op$insert), unclass(delta))
}

delta_tokens = function(delta) {
  tokens = list()
  stack = list()
  add = function(type, key = NULL, value = NULL, text = NULL) {
    list(type = type, key = key, value = value, text = text)
  }
  close_until = function(n) {
    while (length(stack) > n) {
      top = length(stack)
      tokens[[length(tokens) + 1]] <<- add("close", names(stack)[top], stack[[top]])
      stack <<- stack[-top]
    }
  }
  runs = delta_runs(delta)
  run_marks_all = lapply(runs, function(op) run_marks(op$attributes))
  lasts = function(r, key) {
    n = 0
    while (r + n <= length(runs) && identical(run_marks_all[[r + n]][[key]], run_marks_all[[r]][[key]])) {
      n = n + 1
    }
    n
  }
  for (r in seq_along(runs)) {
    op = runs[[r]]
    marks = run_marks_all[[r]]
    keep = 0
    for (i in seq_along(stack)) {
      key = names(stack)[i]
      if (!key %in% names(marks) || !identical(stack[[i]], marks[[key]])) {
        break
      }
      keep = i
    }
    close_until(keep)
    opening = setdiff(names(marks), names(stack))
    spans = vapply(opening, function(key) lasts(r, key), numeric(1))
    for (key in opening[order(-spans)]) {
      tokens[[length(tokens) + 1]] = add("open", key, marks[[key]])
      stack[[key]] = marks[[key]]
    }
    tokens[[length(tokens) + 1]] = add("text", text = op$insert)
  }
  close_until(0)
  tokens
}

scalar_mark = function(value) {
  if (!is.atomic(value) || length(value) != 1) {
    return(NULL)
  }
  if (is.logical(value)) tolower(as.character(value)) else as.character(value)
}

html_escape = function(x, attribute = FALSE) {
  x = gsub("&", "&amp;", x, fixed = TRUE)
  x = gsub("<", "&lt;", x, fixed = TRUE)
  x = gsub(">", "&gt;", x, fixed = TRUE)
  if (attribute) {
    x = gsub("\"", "&quot;", x, fixed = TRUE)
  }
  x
}

html_tags = c(
  bold = "strong",
  italic = "em",
  underline = "u",
  highlight = "mark",
  code = "code"
)

html_open = function(key, value) {
  if (key %in% names(html_tags)) {
    return(paste0("<", html_tags[[key]], ">"))
  }
  if (key == "link" && is.character(value) && length(value) == 1) {
    return(paste0("<a href=\"", html_escape(value, attribute = TRUE), "\">"))
  }
  name = paste0("data-", gsub("[^a-z0-9-]", "-", tolower(key)))
  value = scalar_mark(value)
  if (is.null(value)) {
    return(paste0("<span ", name, ">"))
  }
  paste0("<span ", name, "=\"", html_escape(value, attribute = TRUE), "\">")
}

html_close = function(key, value) {
  if (key %in% names(html_tags)) {
    return(paste0("</", html_tags[[key]], ">"))
  }
  if (key == "link" && is.character(value) && length(value) == 1) {
    return("</a>")
  }
  "</span>"
}

delta_html = function(delta, custom = list()) {
  pieces = vapply(
    delta_tokens(delta),
    function(token) {
      if (token$type == "text") {
        return(html_escape(token$text))
      }
      delims = if (token$key %in% names(custom)) {
        custom_delims(custom[[token$key]], token$value, token$key)
      } else {
        c(html_open(token$key, token$value), html_close(token$key, token$value))
      }
      if (token$type == "open") delims[1] else delims[2]
    },
    character(1)
  )
  paste(pieces, collapse = "")
}

markdown_escape = function(x) {
  gsub("([\\\\`*_\\[\\]<>])", "\\\\\\1", x, perl = TRUE)
}

markdown_link_target = function(url) {
  if (grepl("[[:space:]()<>]", url)) {
    paste0("<", gsub(">", "%3E", gsub("<", "%3C", url, fixed = TRUE), fixed = TRUE), ">")
  } else {
    url
  }
}

markdown_delims = function(key, value, code_text) {
  if (key == "bold") {
    return(c("**", "**"))
  }
  if (key == "italic") {
    return(c("*", "*"))
  }
  if (key == "underline") {
    return(c("<u>", "</u>"))
  }
  if (key == "code") {
    ticks = if (grepl("`", code_text, fixed = TRUE)) "``" else "`"
    pad = if (grepl("^`|`$", code_text)) " " else ""
    return(c(paste0(ticks, pad), paste0(pad, ticks)))
  }
  if (key == "link" && is.character(value) && length(value) == 1) {
    return(c("[", paste0("](", markdown_link_target(value), ")")))
  }
  c("", "")
}

delta_markdown = function(delta, custom = list()) {
  tokens = delta_tokens(delta)
  n = length(tokens)
  text = character(n)
  shift = logical(n)
  in_code = FALSE
  code_close = ""
  for (i in seq_len(n)) {
    token = tokens[[i]]
    if (token$type == "text") {
      text[i] = if (in_code) token$text else markdown_escape(token$text)
      next
    }
    if (token$key %in% names(custom)) {
      delims = custom_delims(custom[[token$key]], token$value, token$key)
      text[i] = if (token$type == "open") delims[1] else delims[2]
      shift[i] = TRUE
      next
    }
    code_text = ""
    if (token$key == "code" && token$type == "open") {
      j = i + 1
      while (j <= n && !(tokens[[j]]$type == "close" && tokens[[j]]$key == "code")) {
        if (tokens[[j]]$type == "text") code_text = paste0(code_text, tokens[[j]]$text)
        j = j + 1
      }
    }
    delims = markdown_delims(token$key, token$value, code_text)
    if (token$key == "code") {
      in_code = token$type == "open"
      if (in_code) {
        code_close = delims[2]
      } else {
        delims[2] = code_close
      }
    }
    text[i] = if (token$type == "open") delims[1] else delims[2]
    shift[i] = token$key %in% c("bold", "italic", "link")
  }
  types = vapply(tokens, `[[`, character(1), "type")
  for (i in seq_len(n)) {
    if (types[i] != "text") {
      next
    }
    first = i
    while (first > 1 && types[first - 1] == "open" && shift[first - 1]) {
      first = first - 1
    }
    lead = regmatches(text[i], regexpr("^[[:space:]]*", text[i]))
    if (first < i && nzchar(lead)) {
      text[i] = substring(text[i], nchar(lead) + 1)
      text[first] = paste0(lead, text[first])
    }
    last = i
    while (last < n && types[last + 1] == "close" && shift[last + 1]) {
      last = last + 1
    }
    trail = regmatches(text[i], regexpr("[[:space:]]*$", text[i]))
    if (last > i && nzchar(trail)) {
      text[i] = substring(text[i], 1, nchar(text[i]) - nchar(trail))
      text[last] = paste0(text[last], trail)
    }
  }
  paste(text, collapse = "")
}

style_run = function(text, marks, custom = list()) {
  for (key in rev(names(marks))) {
    value = marks[[key]]
    if (key %in% names(custom)) {
      text = custom_style(custom[[key]], text, value, key)
      next
    }
    text = switch(
      key,
      bold = cli::style_bold(text),
      italic = cli::style_italic(text),
      underline = cli::style_underline(text),
      code = cli::col_cyan(text),
      highlight = cli::bg_br_yellow(cli::col_black(text)),
      link = if (is.character(value) && length(value) == 1) {
        cli::style_hyperlink(cli::col_blue(text), value)
      } else {
        text
      },
      text
    )
  }
  text
}

delta_ansi = function(delta, custom = list()) {
  styled = vapply(
    delta_runs(delta),
    function(op) style_run(op$insert, run_marks(op$attributes), custom),
    character(1)
  )
  cli::ansi_string(paste(styled, collapse = ""))
}

markdown_marks = c("bold", "italic", "underline", "code", "link")
ansi_marks = c(markdown_marks, "highlight")

dropped_marks = function(delta, supported, custom = list()) {
  keys = character()
  for (op in delta_runs(delta)) {
    marks = run_marks(op$attributes)
    for (key in names(marks)) {
      expressible = key %in% names(custom) || (key %in% supported &&
        (key != "link" || (is.character(marks[[key]]) && length(marks[[key]]) == 1)))
      if (!expressible) {
        keys = c(keys, key)
      }
    }
  }
  unique(keys)
}

check_dropped_marks = function(delta, supported, fn, strict, custom = list(), call = rlang::caller_env()) {
  keys = dropped_marks(delta, supported, custom)
  if (length(keys) == 0) {
    return(invisible())
  }
  message = c(
    "{.fn {fn}} cannot show the {cli::qty(length(keys))}mark{?s} {.field {keys}}, so {?it is/they are} left out.",
    i = "Use {.fn text_html} to keep every mark, or give {.arg marks} a way to show {cli::qty(length(keys))}{?it/them}."
  )
  if (strict) {
    cli::cli_abort(message, class = "creditor_dropped_marks", call = call)
  }
  cli::cli_warn(message, class = "creditor_dropped_marks", call = call)
}

delta_formats = c("markdown", "html", "ansi", "list")

S7::method(format, S7::new_S3_class("loro_delta")) = function(
  x,
  ...,
  format = getOption("creditor.delta_format", "markdown")
) {
  format = rlang::arg_match(format, delta_formats)
  if (length(delta_runs(x)) == 0) {
    return("<loro_delta> (empty)")
  }
  body = switch(
    format,
    markdown = delta_markdown(x),
    html = delta_html(x),
    ansi = delta_ansi(x),
    list = paste(utils::capture.output(utils::str(unclass(x))), collapse = "\n")
  )
  lines = c("<loro_delta>", strsplit(body, "\n", fixed = TRUE)[[1]])
  supported = switch(format, markdown = markdown_marks, ansi = ansi_marks, NULL)
  if (!is.null(supported)) {
    keys = dropped_marks(x, supported)
    if (length(keys)) {
      them = if (length(keys) == 1) "it" else "them"
      note = paste0(
        "(not shown: ", paste(keys, collapse = ", "),
        "; print with format = \"html\" to see ", them, ")"
      )
      lines = c(lines, cli::col_grey(note))
    }
  }
  lines
}

S7::method(print, S7::new_S3_class("loro_delta")) = function(
  x,
  ...,
  format = getOption("creditor.delta_format", "markdown")
) {
  cli::cat_line(base::format(x, format = format))
  invisible(x)
}

#' @exportS3Method utils::str
str.loro_delta = function(object, ...) {
  utils::str(unclass(object), ...)
}

check_renderers = function(marks, kind, arg = "marks", call = rlang::caller_env()) {
  if (is.null(marks)) {
    return(list())
  }
  keys = names(marks)
  if (!is.list(marks) || is.object(marks) || length(marks) == 0 && !is.null(keys) ||
    (length(marks) > 0 && (is.null(keys) || any(!nzchar(keys)) || anyDuplicated(keys)))) {
    cli::cli_abort(
      "{.arg {arg}} must be {.code NULL} or a list named by mark key, with each key once.",
      call = call
    )
  }
  for (key in keys) {
    spec = marks[[key]]
    ok = if (kind == "style") {
      is.function(spec)
    } else {
      is.function(spec) || (is.character(spec) && length(spec) == 2 && !anyNA(spec))
    }
    if (!ok) {
      want = if (kind == "style") {
        "a function that styles the text"
      } else {
        "two strings (the opening and closing text) or a function of the mark value returning them"
      }
      cli::cli_abort("{.code {arg}${key}} must be {want}.", call = call)
    }
  }
  marks
}

custom_delims = function(spec, value, key) {
  out = if (is.function(spec)) spec(value) else spec
  if (!is.character(out) || length(out) != 2 || anyNA(out)) {
    cli::cli_abort(
      "The function in {.code marks${key}} must return two strings, the opening and closing text.",
      call = NULL
    )
  }
  out
}

custom_style = function(spec, text, value, key) {
  out = if ("value" %in% names(formals(spec))) spec(text, value = value) else spec(text)
  if (!is.character(out) || length(out) != 1 || is.na(out)) {
    cli::cli_abort("The function in {.code marks${key}} must return one string.", call = NULL)
  }
  out
}
