note_doc = function() {
  doc = loro_doc(peer_id = 1)
  note = doc_map(doc, "note")
  map_set(note, "title", "Groceries")
  items = map_set_container(note, "items", "list")
  list_push(items, "milk")
  list_push(items, list(qty = 2L))
  text_insert(doc_text(doc, "body"), 1, "Hello")
  doc
}

test_that("values are found by path", {
  doc = note_doc()
  expect_identical(doc_get_path(doc, "note/title"), "Groceries")
  expect_identical(doc_get_path(doc, "note/items/0"), "milk")
  expect_identical(doc_get_path(doc, "note/items/1"), list(qty = 2L))
  expect_null(doc_get_path(doc, "note/missing"))
  expect_null(doc_get_path(doc, "note/items/9"))
  expect_null(doc_get_path(doc, "nowhere"))
})

test_that("containers are returned as handles", {
  doc = note_doc()
  items = doc_get_path(doc, "note/items")
  expect_s3_class(items, "creditor::loro_list")
  list_push(items, "eggs")
  expect_identical(doc_get_path(doc, "note/items/2"), "eggs")

  expect_s3_class(doc_get_path(doc, "note"), "creditor::loro_map")
  expect_identical(text_get(doc_get_path(doc, "body")), "Hello")
})

test_that("tree nodes are reachable by id", {
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "outline")
  node = tree_create(tree)
  map_set(tree_meta(tree, node), "title", "Intro")
  expect_identical(doc_get_path(doc, paste0("outline/", node, "/title")), "Intro")
})

test_that("JSONPath returns every match", {
  doc = note_doc()
  expect_identical(doc_jsonpath(doc, "$.note.title"), list("Groceries"))
  expect_identical(doc_jsonpath(doc, "$.note.items[*]"), list("milk", list(qty = 2L)))
  expect_identical(doc_jsonpath(doc, "$.note.items[0]"), list("milk"))
  expect_identical(doc_jsonpath(doc, "$.nowhere"), list())

  matches = doc_jsonpath(doc, "$.note.items")
  expect_length(matches, 1)
  expect_s3_class(matches[[1]], "creditor::loro_list")
})

test_that("path arguments are validated", {
  doc = note_doc()
  expect_error(doc_get_path(doc, 1), "path")
  expect_error(doc_jsonpath(doc, "$$[bad"), "JSONPath")
  expect_error(doc_jsonpath("doc", "$"), "loro_doc")
})
