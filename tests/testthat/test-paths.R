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

test_that("path syntax cannot reach some keys, but JSONPath can", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  map_set(map, "a/b", "slash")
  map_set(map, "0", "zero")
  map_set(map, "", "empty")
  map_set(map, "é", "accent")
  map_set(map_set_container(map, "a", "map"), "b", "nested")

  expect_identical(doc_get_path(doc, "m/a/b"), "nested")
  expect_null(doc_get_path(doc, "m/0"))
  expect_identical(doc_get_path(doc, "m/"), "empty")
  expect_identical(doc_get_path(doc, "m/é"), "accent")

  expect_identical(doc_jsonpath(doc, "$.m['a/b']"), list("slash"))
  expect_identical(doc_jsonpath(doc, "$.m['0']"), list("zero"))
  expect_identical(doc_jsonpath(doc, "$.m['']"), list("empty"))
})

test_that("paths index into lists and text with 0-based positions", {
  doc = loro_doc()
  items = doc_list(doc, "l")
  list_push(items, "x")
  list_push(items, "y")
  text_insert(doc_text(doc, "t"), 1, "hi")
  counter_increment(doc_counter(doc, "c"))

  expect_identical(doc_get_path(doc, "l/1"), "y")
  expect_null(doc_get_path(doc, "l/2"))
  expect_null(doc_get_path(doc, "l/-1"))
  expect_identical(doc_get_path(doc, "t/0"), "h")
  expect_null(doc_get_path(doc, "c/0"))
})

test_that("JSONPath filters and slices work", {
  doc = loro_doc()
  items = doc_list(doc, "items")
  for (qty in c(1, 2, 3)) list_push(items, list(qty = qty))

  expect_identical(doc_jsonpath(doc, "$.items[?(@.qty > 1.5)]"), list(list(qty = 2), list(qty = 3)))
  expect_identical(doc_jsonpath(doc, "$.items[-1:]"), list(list(qty = 3)))
  expect_identical(doc_jsonpath(doc, "$.items[0,2].qty"), list(1, 3))
})

test_that("unsupported JSONPath features are reported as such", {
  doc = loro_doc()
  map_set(doc_map(doc, "m"), "k", 1L)
  list_push(doc_list(doc, "l"), "xyz")
  tree_create(doc_tree(doc, "tr"))

  expect_error(doc_jsonpath(doc, "$..k"), "does not support")
  expect_error(doc_jsonpath(doc, "$.tr[*]"), "does not support")
  expect_error(doc_jsonpath(doc, '$.l[?match(@, "x.*")]'), "does not support")
  expect_identical(doc_jsonpath(doc, "$.m.k"), list(1L))
  text_insert(doc_text(doc, "t"), 1, "still usable")
  expect_identical(text_get(doc_text(doc, "t")), "still usable")
})
