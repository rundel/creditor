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

  text_delete(text, 8, 1)
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
  expect_error(text_delete(text, 2, 10))
  expect_error(text_get(doc), "loro_text")
  expect_error(text_get(doc_map(doc, "m")), "loro_text")
  expect_identical(text_get(text), "abc")
})
