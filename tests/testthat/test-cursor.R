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
  text_delete(text, 3, 3)
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

test_that("a list cursor follows its element", {
  for (make in list(doc_list, doc_movable_list)) {
    doc = loro_doc()
    items = make(doc)
    for (x in c("a", "b", "c")) list_push(items, x)

    cursor = list_cursor(items, 2)
    expect_type(cursor, "raw")
    expect_identical(cursor_pos(doc, cursor), 2L)

    list_insert(items, 1, "z")
    expect_identical(cursor_pos(doc, cursor), 3L)
    list_delete(items, 1:2)
    expect_identical(cursor_pos(doc, cursor), 1L)
    expect_identical(list_get(items, cursor_pos(doc, cursor)), "b")

    end = list_cursor(items, list_length(items) + 1)
    list_push(items, "d")
    expect_identical(cursor_pos(doc, end), list_length(items) + 1L)

    expect_error(list_cursor(items, 9), "pos")
    expect_error(list_cursor(items, 0), "pos")
  }
  expect_error(list_cursor(doc_text(loro_doc()), 1), "loro_list")
})

test_that("a movable list cursor survives other moves but not its own", {
  doc = loro_doc()
  items = doc_movable_list(doc)
  for (x in c("a", "b", "c")) list_push(items, x)

  on_b = list_cursor(items, 2)
  list_move(items, 1, 3)
  expect_identical(list_get(items, cursor_pos(doc, on_b)), "b")
  list_set(items, 1, "B")
  expect_identical(cursor_pos(doc, on_b), 1L)

  list_move(items, 1, 2)
  expect_error(cursor_pos(doc, on_b), "relative position")
})

test_that("the side of a cursor decides which way it leans", {
  doc = loro_doc()
  text = doc_text(doc)
  right = text_cursor(text, 1, "right")
  left = text_cursor(text, 1, "left")
  text_insert(text, 1, "ab")
  expect_identical(cursor_pos(doc, right), 3L)
  expect_identical(cursor_pos(doc, left), 1L)
})

test_that("cursors resolve sensibly after their surroundings are deleted", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "abcdef")
  middle = text_cursor(text, 4)
  end = text_cursor(text, 7, "right")

  text_delete(text, 2, 5)
  expect_identical(cursor_pos(doc, middle), 2L)
  expect_identical(cursor_pos(doc, end), 3L)
  text_insert(text, 2, "XYZ")
  expect_identical(cursor_pos(doc, middle), 5L)
})

test_that("a cursor follows checkout", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "abcd")
  doc_commit(doc)
  version = doc_frontiers(doc)
  cursor = text_cursor(text, 3)
  text_insert(text, 1, "zz")
  doc_commit(doc)
  late = text_cursor(text, 1)
  expect_identical(cursor_pos(doc, cursor), 5L)

  doc_checkout(doc, version)
  expect_identical(cursor_pos(doc, cursor), 3L)
  expect_error(cursor_pos(doc, late), "relative position")
  doc_checkout(doc)
  expect_identical(cursor_pos(doc, cursor), 5L)
})

test_that("a cursor outlives the removal of its container", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  text = loro_text()
  map_set(map, t = text)
  text_insert(text, 1, "abc")
  cursor = text_cursor(text, 2)
  map_delete(map, "t")
  expect_identical(cursor_pos(doc, cursor), 2L)
})

test_that("a cursor from an unrelated document or damaged bytes is an error", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "abc")
  cursor = text_cursor(doc_text(doc), 2)

  other = loro_doc(peer_id = 2)
  expect_error(cursor_pos(other, cursor), "relative position")
  expect_error(cursor_pos(doc, raw()))
  expect_error(cursor_pos(doc, cursor[-length(cursor)]))
  expect_identical(cursor_pos(doc, cursor), 2L)
})
