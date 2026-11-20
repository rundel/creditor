test_that("text can be inserted, deleted, and read back", {
  text = doc_text(loro_doc())
  expect_identical(text_get(text), "")
  expect_identical(text_length(text), 0L)

  text_insert(text, 1, "Hello world")
  text_insert(text, 12, "!")
  expect_identical(text_get(text), "Hello world!")

  text_delete(text, 1, 6)
  expect_identical(text_get(text), "world!")
  expect_identical(text_length(text), 6L)
})

test_that("positions count code points", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "héllo \U0001F600")
  expect_identical(text_length(text), 7L)

  text_insert(text, 3, "X")
  expect_identical(text_get(text), "héXllo \U0001F600")

  text_delete(text, 8, 8)
  expect_identical(text_get(text), "héXllo ")
})

test_that("named text containers are independent", {
  doc = loro_doc()
  text_insert(doc_text(doc, "one"), 1, "a")
  text_insert(doc_text(doc, "two"), 1, "b")
  expect_identical(text_get(doc_text(doc, "one")), "a")
  expect_identical(text_get(doc_text(doc, "two")), "b")
  expect_identical(doc_value(doc), list(one = "a", two = "b"))
})

test_that("invalid edits are errors", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "abc")
  expect_error(text_insert(text, 0, "x"), "pos")
  expect_error(text_insert(text, 1.5, "x"), "pos")
  expect_error(text_insert(text, 1, NA_character_), "value")
  expect_error(text_insert(text, 10, "x"))
  expect_error(text_delete(text, 2, 11))
  expect_error(text_get(doc_map(doc)), "loro_text")
  expect_error(text_get(doc_map(doc, "m")), "loro_text")
  expect_identical(text_get(text), "abc")
})

test_that("a range of text can be read", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "Hello \U0001F600 world")
  expect_identical(text_sub(text, 1, 5), "Hello")
  expect_identical(text_sub(text, 7, 7), "\U0001F600")
  expect_identical(text_sub(text, 9, 13), "world")
  expect_identical(text_sub(text, 1, 0), "")
  expect_error(text_sub(text, 10, 108))
  expect_error(text_sub(text, 0, 0), "start")
  expect_identical(text_sub(text), "Hello \U0001F600 world")
  expect_identical(text_sub(text, 9), "world")
  expect_identical(text_sub(text, end = 5), "Hello")
})

test_that("a range of text can be replaced", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "Hello world")
  text_replace(text, 1, 5, "Howdy")
  expect_identical(text_get(text), "Howdy world")
  text_replace(text, 6, 5, ",")
  expect_identical(text_get(text), "Howdy, world")
  text_replace(text, 6, 12, "")
  expect_identical(text_get(text), "Howdy")
  expect_error(text_replace(text, 99, 99, "x"))
  expect_identical(text_get(text), "Howdy")
})

test_that("text can be updated line by line", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "line one\nline two\nline three\n")
  text_mark(text, 1, 8, bold = TRUE)

  new = "line one\nline 2\nline three\nline four\n"
  text_update(text, new, by = "line")
  expect_identical(text_get(text), new)
  expect_identical(unclass(text_delta(text, 1, 8)), list(list(insert = "line one", attributes = list(bold = TRUE))))
  expect_error(text_update(text, new, by = "word"))
})

test_that("length is available in each unit", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "a\U0001F600éb")
  expect_identical(text_length(text), 4L)
  expect_identical(text_length(text, "unicode"), 4L)
  expect_identical(text_length(text, "utf16"), 5L)
  expect_identical(text_length(text, "utf8"), 8L)
  expect_error(text_length(text, "words"))
})

test_that("positions convert between units", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "a\U0001F600éb")
  convert = function(pos, from, to) {
    vapply(pos, function(p) text_convert_pos(text, p, from, to), integer(1))
  }

  expect_identical(convert(1:5, "unicode", "utf16"), c(1L, 2L, 4L, 5L, 6L))
  expect_identical(convert(c(1, 2, 4, 5, 6), "utf16", "unicode"), 1:5)
  expect_identical(convert(1:5, "unicode", "utf8"), c(1L, 2L, 6L, 8L, 9L))
  expect_identical(convert(c(1, 2, 6, 8, 9), "utf8", "unicode"), 1:5)
  expect_identical(text_convert_pos(text, 3), 4L)

  expect_identical(text_convert_pos(text, 3, "utf16", "unicode"), 2L)
  expect_identical(text_convert_pos(text, 99), NA_integer_)
  expect_error(text_convert_pos(text, 0), "pos")
  expect_error(text_convert_pos(text, 1, "utf16", "words"))
})

test_that("a converted position addresses the same character", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "\U0001F600\U0001F600x")
  utf16_offset_of_x = 4L
  pos = text_convert_pos(text, utf16_offset_of_x + 1L, "utf16", "unicode")
  expect_identical(text_sub(text, pos, pos), "x")
})

test_that("out of range errors name the 1-based position given", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "abc")

  expect_error(text_insert(text, 10, "x"), "at most 4.*not 10")
  expect_error(text_delete(text, 2, 11), "range is 2 to 11.*length 3")
  expect_error(text_replace(text, 5, 4, "x"), "range is 5 to 4")
  expect_error(text_delete(text, 3, 1), "at least 2")
  expect_error(text_sub(text, 4, 4), "range is 4 to 4")
  expect_identical(text_get(text), "abc")
})

test_that("an empty range is allowed only at a valid position", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "abc")

  expect_identical(text_sub(text, 4, 3), "")
  text_delete(text, 4, 3)
  text_replace(text, 4, 3, "")
  expect_identical(unclass(text_delta(text, 4, 3)), list())

  expect_error(text_sub(text, 99, 98), "range is 99 to 98")
  expect_error(text_delete(text, 99, 98), "range is 99 to 98")
  expect_error(text_delta(text, 99, 98), "range is 99 to 98")
  expect_error(text_replace(text, 99, 98, ""), "range is 99 to 98")
  expect_identical(text_get(text), "abc")
})

test_that("range arithmetic does not overflow", {
  text = doc_text(loro_doc())
  text_insert(text, 1, "abc")
  big = .Machine$integer.max
  expect_no_warning(expect_error(text_sub(text, 2, big), "range"))
  expect_no_warning(expect_error(text_delete(text, 2, big), "range"))
  expect_no_warning(expect_error(text_mark(text, 2, big, bold = TRUE), "range"))
  expect_no_warning(expect_error(text_delta(text, 2, big), "range"))
  expect_no_warning(expect_error(text_sub(text, 2, big + 1), "end"))
})

test_that("combining characters and joined emoji count per code point", {
  text = doc_text(loro_doc())
  family = "\U0001F468‍\U0001F469‍\U0001F467"
  text_insert(text, 1, paste0("é", family, "z"))
  expect_identical(text_length(text), 8L)
  expect_identical(text_sub(text, 1, 2), "é")
  expect_identical(text_sub(text, 3, 7), family)
  expect_identical(text_sub(text, 8, 8), "z")
})

test_that("text can be appended and read with base functions", {
  text = doc_text(loro_doc())
  expect_identical(text_push(text, "Hello"), text)
  text_push(text, " \U0001F600")
  expect_identical(as.character(text), "Hello \U0001F600")
  expect_identical(length(text), 7L)
  expect_error(text_push(text, 1), "value")
})
