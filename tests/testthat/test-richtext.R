plain = function(x) list(insert = x)
marked = function(x, ...) list(insert = x, attributes = list(...))

test_that("marks can be added and removed", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "Hello world")
  expect_identical(text_delta(text), list(plain("Hello world")))

  text_mark(text, 1, 5, "bold")
  expect_identical(text_delta(text), list(marked("Hello", bold = TRUE), plain(" world")))

  text_mark(text, 7, 5, "link", "https://loro.dev")
  text_unmark(text, 1, 2, "bold")
  expect_identical(
    text_delta(text),
    list(
      plain("He"),
      marked("llo", bold = TRUE),
      plain(" "),
      marked("world", link = "https://loro.dev")
    )
  )
  expect_identical(text_get(text), "Hello world")
})

test_that("overlapping marks combine", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "abcdef")
  text_mark(text, 1, 4, "bold")
  text_mark(text, 3, 4, "italic")
  expect_identical(
    text_delta(text),
    list(
      marked("ab", bold = TRUE),
      marked("cd", bold = TRUE, italic = TRUE),
      marked("ef", italic = TRUE)
    )
  )
})

test_that("mark ranges count code points", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "a\U0001F600b")
  text_mark(text, 2, 1, "bold")
  expect_identical(
    text_delta(text),
    list(plain("a"), marked("\U0001F600", bold = TRUE), plain("b"))
  )
})

test_that("expand behavior follows the style configuration", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "ab")
  text_mark(text, 1, 2, "bold")
  text_insert(text, 3, "c")
  expect_identical(text_delta(text), list(marked("abc", bold = TRUE)))

  text = doc_text(loro_doc())
  text_insert(text, 1, "ab")
  text_mark(text, 1, 2, "link", "u")
  text_insert(text, 3, "c")
  expect_identical(text_delta(text), list(marked("ab", link = "u"), plain("c")))
})

test_that("mark keys must be configured", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "abc")
  expect_error(text_mark(text, 1, 1, "author", "x"), "doc_config_text_style")

  doc_config_text_style(doc, author = "none")
  text_mark(text, 1, 1, "author", "x")
  text_mark(text, 2, 1, "bold")
  expect_identical(
    text_delta(text),
    list(marked("a", author = "x"), marked("b", bold = TRUE), plain("c"))
  )

  expect_error(text_mark(text, 1, 1, "other"), "doc_config_text_style")
  doc_config_text_style(doc, default = "after")
  text_mark(text, 3, 1, "other")
  expect_identical(text_delta(text)[[3]], marked("c", other = TRUE))
})

test_that("style configuration is validated", {
  doc = loro_doc()
  expect_error(doc_config_text_style(doc, "none"), "named")
  expect_error(doc_config_text_style(doc, a = "sideways"), "one of")
  expect_error(doc_config_text_style(doc, `a:b` = "none"), ":")
  expect_error(doc_config_text_style(doc, default = "nope"), "default")
})

test_that("invalid marks are errors", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "abc")
  expect_error(text_mark(text, 1, 0, "bold"), "len")
  expect_error(text_mark(text, 2, 10, "bold"))
  expect_error(text_mark(text, 1, 1, "a:b"), ":")
  expect_identical(text_delta(text), list(plain("abc")))
})

test_that("a delta can be applied", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "Hello \U0001F600 world")
  text_apply_delta(text, list(
    list(retain = 7),
    list(insert = "!", attributes = list(bold = TRUE)),
    list(delete = 1)
  ))
  expect_identical(text_get(text), "Hello \U0001F600!world")

  text_apply_delta(text, list(
    list(retain = 5, attributes = list(italic = TRUE)),
    list(retain = 2),
    list(retain = 1, attributes = list(bold = NULL))
  ))
  expect_identical(
    text_delta(text),
    list(marked("Hello", italic = TRUE), plain(" \U0001F600!world"))
  )
})

test_that("text_delta output rebuilds the same rich text", {
  a = doc_text(loro_doc())
  text_insert(a, 1, "Hello world")
  text_mark(a, 1, 5, "bold")
  text_mark(a, 4, 6, "link", "u")

  b = doc_text(loro_doc())
  text_apply_delta(b, text_delta(a))
  expect_identical(text_delta(b), text_delta(a))
})

test_that("malformed deltas are errors", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "abc")
  expect_error(text_apply_delta(text, "x"), "delta")
  expect_error(text_apply_delta(text, list("x")), "named list")
  expect_error(text_apply_delta(text, list(list(retain = 1, insert = "x"))), "exactly one")
  expect_error(text_apply_delta(text, list(list(attributes = list(bold = TRUE)))), "exactly one")
  expect_error(text_apply_delta(text, list(list(retain = -1))), "retain")
  expect_error(text_apply_delta(text, list(list(insert = 1))), "insert")
  expect_error(text_apply_delta(text, list(list(skip = 1))), "fields")
  expect_error(text_apply_delta(text, list(list(retain = 100), list(insert = "x"))))
  expect_identical(text_get(text), "abc")
})

test_that("marks sync and merge with concurrent edits", {
  a = loro_doc(peer_id = 1)
  text_insert(doc_text(a), 1, "Hello world")
  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))

  text_mark(doc_text(a), 1, 5, "bold")
  text_insert(doc_text(b), 3, "XX")

  doc_import(b, doc_export(a, "updates", from = doc_version(b)))
  doc_import(a, doc_export(b, "updates", from = doc_version(a)))

  expect_identical(text_delta(doc_text(a)), text_delta(doc_text(b)))
  expect_identical(
    text_delta(doc_text(a)),
    list(marked("HeXXllo", bold = TRUE), plain(" world"))
  )
})

test_that("text_update applies a minimal diff", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "Hello world")
  text_mark(text, 7, 5, "bold")
  cursor = text_cursor(text, 7)

  text_update(text, "Hello brave new world")
  expect_identical(text_get(text), "Hello brave new world")
  expect_identical(
    text_delta(text),
    list(plain("Hello brave new "), marked("world", bold = TRUE))
  )
  expect_identical(cursor_pos(doc, cursor), 17L)

  text_update(text, "")
  expect_identical(text_get(text), "")
})

test_that("a delta can be taken for a range", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "Hello world")
  text_mark(text, 1, 5, "bold")

  expect_identical(
    text_delta(text, 4, 5),
    list(marked("lo", bold = TRUE), plain(" wo"))
  )
  expect_identical(text_delta(text, 7, 5), list(plain("world")))
  expect_identical(text_delta(text, 1, 0), list())
  expect_identical(text_delta(text, 1, 11), text_delta(text))
  expect_error(text_delta(text, 2), "together")
  expect_error(text_delta(text, len = 2), "together")
  expect_error(text_delta(text, 2, 99))
})
