test_that("a document stands for its default root containers", {
  doc = loro_doc(peer_id = 1)

  expect_identical(text_insert(doc, 1, "Hello"), doc)
  text_push(doc, " world")
  text_mark(doc, 1, 5, bold = TRUE)
  expect_identical(text_get(doc), "Hello world")
  expect_identical(text_sub(doc, 7), "world")
  expect_identical(text_length(doc), 11L)
  expect_identical(text_delta(doc)[[1]]$attributes, list(bold = TRUE))
  expect_identical(cursor_pos(doc, text_cursor(doc, 7)), 7L)

  expect_identical(map_set(doc, theme = "dark", size = 12L), doc)
  expect_identical(map_get(doc, "theme"), "dark")
  expect_identical(map_keys(doc), c("size", "theme"))
  map_delete(doc, "size")
  body = map_set_container(doc, "body", "text")
  text_insert(body, 1, "nested")

  list_push(doc, "a", "b", "c")
  list_delete(doc, 2)
  expect_identical(list_get(doc, 2), "c")
  expect_identical(list_length(doc), 2L)

  counter_increment(doc, 3)
  expect_identical(counter_get(doc), 3)

  node = tree_create(doc, meta = list(title = "Intro"))
  expect_identical(tree_children(doc), node)
  expect_identical(tree_meta(doc, node)$title, "Intro")

  expect_identical(text_get(doc_text(doc)), "Hello world")
  expect_identical(as.list(doc_map(doc)), list(body = "nested", theme = "dark"))
  expect_identical(as.list(doc_list(doc)), list("a", "c"))
  expect_identical(
    names(doc_value(doc)),
    c("counter", "list", "map", "text", "tree")
  )
})

test_that("a document is not a movable list", {
  doc = loro_doc()
  list_push(doc, "a", "b")
  expect_error(list_move(doc, 1, 2), "doc_movable_list")
  expect_error(list_set(doc, 1, "z"), "doc_movable_list")
  expect_error(list_set_container(doc, 1, "map"), "doc_movable_list")
  expect_identical(names(doc_value(doc)), "list")
})

test_that("other objects are still rejected with the handle's class", {
  expect_error(text_insert("doc", 1, "a"), "loro_text")
  expect_error(map_set(doc_text(loro_doc()), a = 1), "loro_map")
  expect_error(container_value(loro_doc()), "loro_container")
})

test_that("edits made through a document sync and reach subscribers", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  events = 0L
  sub = doc_subscribe(a, function(event) events <<- events + 1L)
  on.exit(unsubscribe(sub))

  text_insert(a, 1, "Hello")
  doc_commit(a)
  expect_identical(events, 1L)
  doc_import(b, doc_export(a))
  expect_identical(text_get(b), "Hello")
})
