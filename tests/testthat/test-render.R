marked_text = function(text, ...) {
  doc = loro_doc() |>
    text_insert(1, text)
  marks = list(...)
  for (mark in marks) {
    rlang::inject(text_mark(doc, mark[[1]], mark[[2]], !!!mark[-(1:2)]))
  }
  doc
}

test_that("a delta keeps its list structure and class", {
  doc = marked_text("Hello world", list(1, 5, bold = TRUE))
  delta = text_delta(doc)
  expect_s3_class(delta, "loro_delta")
  expect_identical(delta[[1]], list(insert = "Hello", attributes = list(bold = TRUE)))
  expect_output(str(delta), "List of 2")
  expect_no_match(paste(capture.output(str(delta)), collapse = "\n"), "loro_delta")

  copy = loro_doc()
  text_apply_delta(copy, delta)
  expect_identical(text_delta(copy), delta)
})

test_that("a delta prints as markdown", {
  doc = marked_text("Read the docs", list(1, 4, bold = TRUE), list(10, 13, link = "https://loro.dev"))
  expect_snapshot(text_delta(doc))
  expect_snapshot(text_delta(loro_doc()))
})

test_that("a delta prints in the format asked for", {
  doc = marked_text("Read the docs", list(1, 4, bold = TRUE))
  delta = text_delta(doc)
  expect_snapshot(print(delta, format = "html"))
  expect_identical(
    format(delta, format = "list"),
    c("<loro_delta>", utils::capture.output(utils::str(unclass(delta))))
  )
  rlang::local_options(cli.num_colors = 1)
  expect_identical(format(delta, format = "ansi"), c("<loro_delta>", "Read the docs"))
  rlang::local_options(creditor.delta_format = "html")
  expect_identical(format(delta), c("<loro_delta>", "<strong>Read</strong> the docs"))
  expect_error(print(delta, format = "pdf"), "must be one of")
})

test_that("markdown renders the standard marks", {
  doc = marked_text(
    "Read the docs today, now",
    list(1, 4, bold = TRUE),
    list(10, 13, link = "https://loro.dev"),
    list(15, 19, italic = TRUE),
    list(22, 24, code = TRUE)
  )
  expect_identical(text_markdown(doc), "**Read** the [docs](https://loro.dev) *today*, `now`")
  expect_identical(text_markdown(doc, 1, 8), "**Read** the")
})

test_that("markdown nests overlapping marks and keeps spaces outside delimiters", {
  doc = marked_text("bold and both", list(1, 13, bold = TRUE), list(10, 13, italic = TRUE))
  expect_identical(text_markdown(doc), "**bold and *both***")

  doc = marked_text("a b c", list(1, 3, bold = TRUE))
  expect_identical(text_markdown(doc), "**a b** c")

  doc = marked_text("a b c", list(2, 4, bold = TRUE))
  expect_identical(text_markdown(doc), "a **b** c")
})

test_that("markdown escapes text but not code", {
  doc = marked_text("2*3 [x] a*b", list(9, 11, code = TRUE))
  expect_identical(text_markdown(doc), "2\\*3 \\[x\\] `a*b`")

  doc = marked_text("say `hi`", list(5, 8, code = TRUE))
  expect_identical(text_markdown(doc), "say `` `hi` ``")
})

test_that("markdown writes underline as a tag and drops marks it cannot express", {
  doc = marked_text("under note", list(1, 5, underline = TRUE), list(7, 10, comment = "c"))
  expect_warning(
    expect_identical(text_markdown(doc), "<u>under</u> note"),
    class = "creditor_dropped_marks"
  )

  doc = marked_text("go", list(1, 2, link = "https://example.com/a b"))
  expect_identical(text_markdown(doc), "[go](<https://example.com/a b>)")
})

test_that("html renders every mark", {
  doc = marked_text(
    "Read <the> docs",
    list(1, 4, bold = TRUE),
    list(6, 10, italic = TRUE, comment = "check \"this\""),
    list(12, 15, link = "https://loro.dev/?a=1&b=2", highlight = TRUE)
  )
  expect_identical(
    text_html(doc),
    paste0(
      "<strong>Read</strong> ",
      "<em><span data-comment=\"check &quot;this&quot;\">&lt;the&gt;</span></em> ",
      "<a href=\"https://loro.dev/?a=1&amp;b=2\"><mark>docs</mark></a>"
    )
  )
})

test_that("html writes custom marks as data attributes", {
  doc = loro_doc() |>
    doc_config_text_style(author = "none", reviewed = "none") |>
    text_insert(1, "ab") |>
    text_mark(1, 1, author = "cr") |>
    text_mark(2, 2, reviewed = TRUE)
  expect_identical(
    text_html(doc),
    "<span data-author=\"cr\">a</span><span data-reviewed=\"true\">b</span>"
  )
  expect_warning(expect_identical(text_markdown(doc), "ab"), "author")
})

test_that("rendering an empty text gives an empty string", {
  expect_identical(text_markdown(loro_doc()), "")
  expect_identical(text_html(loro_doc()), "")
})

test_that("ansi styles each mark and is plain text without color support", {
  doc = marked_text(
    "Read the docs",
    list(1, 4, bold = TRUE),
    list(10, 13, link = "https://loro.dev"),
    list(6, 8, comment = "c")
  )
  rlang::local_options(cli.num_colors = 1)
  expect_warning(plain <- text_ansi(doc), "comment", class = "creditor_dropped_marks")
  expect_s3_class(plain, "cli_ansi_string")
  expect_identical(as.character(plain), "Read the docs")

  rlang::local_options(cli.num_colors = 256, cli.hyperlink = FALSE)
  styled = suppressWarnings(text_ansi(doc), classes = "creditor_dropped_marks")
  expect_identical(as.character(cli::ansi_strip(styled)), "Read the docs")
  expect_no_warning(text_ansi(doc, 1, 4))
  expect_identical(as.character(cli::ansi_strip(text_ansi(doc, 1, 4))), "Read")
  expect_match(styled, "\033[1mRead\033[22m", fixed = TRUE)
  expect_match(styled, "\033[34mdocs", fixed = TRUE)
  expect_identical(as.character(text_ansi(loro_doc())), "")
})

test_that("dropped marks warn once per call, or error when strict", {
  doc = loro_doc() |>
    doc_config_text_style(author = "none") |>
    text_insert(1, "a b c") |>
    text_mark(1, 1, author = "x") |>
    text_mark(3, 3, author = "y") |>
    text_mark(5, 5, comment = "z", highlight = TRUE)
  warnings = list()
  withCallingHandlers(
    text_markdown(doc),
    warning = function(w) {
      warnings[[length(warnings) + 1]] <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )
  expect_length(warnings, 1)
  expect_match(warnings[[1]], "marks author, highlight, and comment")

  expect_error(text_markdown(doc, strict = TRUE), class = "creditor_dropped_marks")
  expect_error(text_ansi(doc, strict = TRUE), "marks author and comment")
  expect_no_warning(text_markdown(doc, 2, 2))
  expect_no_warning(text_html(doc))
  expect_error(text_markdown(doc, strict = NA), "strict")
})

test_that("a link without a URL counts as dropped", {
  doc = marked_text("go", list(1, 2, link = TRUE))
  expect_warning(expect_identical(text_markdown(doc), "go"), "link")
})

test_that("printing notes left-out marks instead of warning", {
  doc = loro_doc() |>
    doc_config_text_style(author = "none") |>
    text_insert(1, "ab") |>
    text_mark(1, 1, bold = TRUE) |>
    text_mark(2, 2, author = "cr")
  delta = text_delta(doc)
  expect_no_warning(format(delta))
  expect_snapshot({
    print(delta)
    print(delta, format = "html")
  })
})

test_that("marks can be rendered with given strings or functions", {
  doc = loro_doc() |>
    doc_config_text_style(author = "none") |>
    text_insert(1, "Reviewed by me") |>
    text_mark(1, 8, author = "cr") |>
    text_mark(13, 14, bold = TRUE)
  cite = function(value) c(paste0("<cite title=\"", value, "\">"), "</cite>")

  expect_identical(
    text_html(doc, marks = list(author = cite)),
    "<cite title=\"cr\">Reviewed</cite> by <strong>me</strong>"
  )
  expect_no_warning(
    md <- text_markdown(doc, marks = list(author = function(value) c("", paste0(" [", value, "]"))))
  )
  expect_identical(md, "Reviewed [cr] by **me**")
  expect_warning(
    expect_identical(text_markdown(doc, marks = list(bold = c("__", "__"))), "Reviewed by __me__"),
    "author"
  )
})

test_that("renderer strings may be named before and after", {
  doc = marked_text("ab", list(1, 1, bold = TRUE))
  named = list(bold = function(value) c(before = "[", after = "]"))
  expect_identical(text_markdown(doc, marks = named), "[a]b")
  expect_identical(text_html(doc, marks = list(bold = c(before = "<b>", after = "</b>"))), "<b>a</b>b")
})

test_that("given markdown delimiters keep spaces outside", {
  doc = marked_text("a b c", list(1, 4, highlight = TRUE))
  expect_identical(text_markdown(doc, marks = list(highlight = c("==", "=="))), "==a b== c")
})

test_that("ansi marks can be styled with functions, with or without the value", {
  doc = loro_doc() |>
    doc_config_text_style(author = "none") |>
    text_insert(1, "ab") |>
    text_mark(1, 1, author = "cr")
  expect_identical(
    as.character(text_ansi(doc, marks = list(author = toupper))),
    "Ab"
  )
  expect_identical(
    as.character(text_ansi(doc, marks = list(author = function(text, value) paste0(text, "<", value, ">")))),
    "a<cr>b"
  )
  expect_identical(
    as.character(text_ansi(doc, marks = list(author = c(before = "[", after = "]")))),
    "[a]b"
  )
})

test_that("renderers are validated", {
  doc = loro_doc() |>
    text_insert(1, "ab") |>
    text_mark(1, 1, bold = TRUE)
  expect_error(text_html(doc, marks = list("a")), "named by mark key")
  expect_error(text_html(doc, marks = list(bold = "x")), "two strings")
  expect_error(text_markdown(doc, marks = list(bold = function(value) 1)), "must return two strings")
  expect_error(text_ansi(doc, marks = list(bold = "a")), "function that styles")
  expect_error(text_ansi(doc, marks = list(bold = function(text) 1)), "must return one string")
})
