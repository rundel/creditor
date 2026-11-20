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

delta_html = function(delta) {
  pieces = vapply(
    delta_tokens(delta),
    function(token) {
      switch(
        token$type,
        text = html_escape(token$text),
        open = html_open(token$key, token$value),
        close = html_close(token$key, token$value)
      )
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

delta_markdown = function(delta) {
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

style_run = function(text, marks) {
  for (key in rev(names(marks))) {
    value = marks[[key]]
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

delta_ansi = function(delta) {
  styled = vapply(
    delta_runs(delta),
    function(op) style_run(op$insert, run_marks(op$attributes)),
    character(1)
  )
  cli::ansi_string(paste(styled, collapse = ""))
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
  c("<loro_delta>", strsplit(body, "\n", fixed = TRUE)[[1]])
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
