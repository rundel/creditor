test_that("a cursor follows its character through edits", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "world")

  cursor = text_cursor(text, 1)
  expect_type(cursor, "raw")
  expect_identical(cursor_pos(doc, cursor), 1L)

  text_insert(text, 1, "Hello ")
  expect_identical(cursor_pos(doc, cursor), 7L)

  text_insert(text, 12, "!")
  expect_identical(cursor_pos(doc, cursor), 7L)

  text_delete(text, 1, 3)
  expect_identical(cursor_pos(doc, cursor), 4L)
})

test_that("a cursor survives deletion of its character", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "abcde")
  cursor = text_cursor(text, 3)
  text_delete(text, 3, 1)
  expect_identical(text_get(text), "abde")
  expect_identical(cursor_pos(doc, cursor), 3L)
})

test_that("a cursor can sit at the end of the text", {
  doc = loro_doc()
  text = doc_text(doc)
  expect_identical(cursor_pos(doc, text_cursor(text, 1)), 1L)

  text_insert(text, 1, "abc")
  cursor = text_cursor(text, 4)
  text_insert(text, 4, "def")
  expect_identical(cursor_pos(doc, cursor), 7L)
})

test_that("a cursor resolves on another replica", {
  a = loro_doc(peer_id = 1)
  text_insert(doc_text(a), 1, "Hello world")
  cursor = text_cursor(doc_text(a), 7)

  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))
  text_insert(doc_text(b), 1, ">> ")
  expect_identical(cursor_pos(b, cursor), 10L)
})

test_that("invalid cursor input is an error", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "abc")
  expect_error(text_cursor(text, 0), "pos")
  expect_error(text_cursor(text, 5), "pos")
  expect_error(text_cursor(text, 1, side = "up"))
  expect_error(cursor_pos(doc, "x"), "raw")
  expect_error(cursor_pos(doc, as.raw(1:5)))
  expect_error(cursor_pos(text, text_cursor(text, 1)), "loro_doc")
})
