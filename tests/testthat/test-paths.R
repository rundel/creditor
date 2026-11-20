note_doc = function() {
  doc = loro_doc(peer_id = 1)
  note = doc_map(doc, "note")
  map_set(note, title = "Groceries")
  items = loro_list()
  map_set(note, items = items)
  list_push(items, "milk")
  list_push(items, list(qty = 2L))
  text_insert(doc_text(doc, "body"), 1, "Hello")
  doc
}

test_that("values are found by path", {
  doc = note_doc()
  expect_identical(doc_get(doc, "note", "title"), "Groceries")
  expect_identical(doc_get(doc, "note", "items", 1), "milk")
  expect_identical(doc_get(doc, "note", "items", 2), list(qty = 2L))
  expect_null(doc_get(doc, "note", "missing"))
  expect_null(doc_get(doc, "note", "items", 10))
  expect_null(doc_get(doc, "nowhere"))
})

test_that("containers are returned as handles", {
  doc = note_doc()
  items = doc_get(doc, "note", "items")
  expect_s3_class(items, "creditor::loro_list")
  list_push(items, "eggs")
  expect_identical(doc_get(doc, "note", "items", 3), "eggs")

  expect_s3_class(doc_get(doc, "note"), "creditor::loro_map")
  expect_identical(text_get(doc_get(doc, "body")), "Hello")
})

test_that("tree nodes are reachable by id", {
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "outline")
  node = tree_create(tree)
  map_set(tree_meta(tree, node), title = "Intro")
  expect_identical(doc_get(doc, "outline", node, "title"), "Intro")
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
  expect_error(doc_get(doc, 1), "root container")
  expect_error(doc_get(doc), "path steps")
  expect_error(doc_get(doc, "note", 1.5), "path steps")
  expect_error(doc_get(doc, "note", key = "title"), "named")
  expect_error(doc_jsonpath(doc, "$$[bad"), "JSONPath")
  expect_error(doc_jsonpath("doc", "$"), "loro_doc")
})

test_that("path steps reach any map key", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  map_set(map, "a/b" = "slash", "0" = "zero", "é" = "accent")
  map[[""]] = "empty"
  map_set(map, a = loro_map(b = "nested"))

  expect_identical(doc_get(doc, "m", "a", "b"), "nested")
  expect_identical(doc_get(doc, "m", "a/b"), "slash")
  expect_identical(doc_get(doc, "m", "0"), "zero")
  expect_identical(doc_get(doc, "m", ""), "empty")
  expect_identical(doc_get(doc, "m", "é"), "accent")
  expect_null(doc_get(doc, "m", 1))
  expect_null(doc_get(doc, "m/a"))

  expect_identical(doc_jsonpath(doc, "$.m['a/b']"), list("slash"))
  expect_identical(doc_jsonpath(doc, "$.m['0']"), list("zero"))
  expect_identical(doc_jsonpath(doc, "$.m['']"), list("empty"))
})

test_that("path steps index lists with 1-based positions", {
  doc = loro_doc()
  items = doc_list(doc, "l")
  list_push(items, "x", "y", list(deep = list("p", "q")))
  text_insert(doc_text(doc, "t"), 1, "hi")
  counter_increment(doc_counter(doc, "c"))

  expect_identical(doc_get(doc, "l", 2), "y")
  expect_null(doc_get(doc, "l", 4))
  expect_null(doc_get(doc, "l", 0))
  expect_null(doc_get(doc, "l", -1))
  expect_null(doc_get(doc, "l", "x"))
  expect_identical(doc_get(doc, "l", 3, "deep", 2), "q")
  expect_null(doc_get(doc, "l", 3, "deep", 3))
  expect_null(doc_get(doc, "l", 3, "nope"))
  expect_identical(doc_get(doc, !!!list("l", 1)), "x")
  expect_null(doc_get(doc, "t", 1))
  expect_null(doc_get(doc, "c", 1))
})

test_that("looking up a path does not create containers", {
  doc = loro_doc()
  expect_null(doc_get(doc, "nowhere", "key"))
  expect_identical(doc_value(doc), structure(list(), names = character()))
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
  map_set(doc_map(doc, "m"), k = 1L)
  list_push(doc_list(doc, "l"), "xyz")
  tree_create(doc_tree(doc, "tr"))

  expect_error(doc_jsonpath(doc, "$..k"), "does not support")
  expect_error(doc_jsonpath(doc, "$.tr[*]"), "does not support")
  expect_error(doc_jsonpath(doc, '$.l[?match(@, "x.*")]'), "does not support")
  expect_identical(doc_jsonpath(doc, "$.m.k"), list(1L))
  text_insert(doc_text(doc, "t"), 1, "still usable")
  expect_identical(text_get(doc_text(doc, "t")), "still usable")
})
