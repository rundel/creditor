test_that("root handles have the expected classes and ids", {
  doc = loro_doc()
  text = doc_text(doc, "t")
  map = doc_map(doc, "m")
  list = doc_list(doc, "l")

  expect_s3_class(text, "creditor::loro_text")
  expect_s3_class(map, "creditor::loro_map")
  expect_s3_class(list, "creditor::loro_list")

  expect_identical(container_id(text), "cid:root-t:Text")
  expect_identical(container_id(map), "cid:root-m:Map")
  expect_identical(container_id(list), "cid:root-l:List")
})

test_that("handles to the same container share state", {
  doc = loro_doc()
  text_insert(doc_text(doc), 1, "x")
  expect_identical(text_get(doc_text(doc)), "x")
})

test_that("a handle keeps its document alive", {
  text = local({
    doc = loro_doc()
    doc_text(doc)
  })
  invisible(gc())
  text_insert(text, 1, "still here")
  expect_identical(text_get(text), "still here")
})

test_that("container_value expands nested containers", {
  doc = loro_doc()
  root = doc_map(doc, "root")
  items = loro_list()
  map_set(root, items = items)
  body = loro_text()
  list_push(items, body)
  text_insert(body, 1, "nested")
  list_push(items, 2L)

  expect_identical(container_value(body), "nested")
  expect_identical(container_value(items), list("nested", 2L))
  expect_identical(container_value(root), list(items = list("nested", 2L)))
  expect_identical(doc_value(doc), list(root = list(items = list("nested", 2L))))
})

test_that("nested containers sync and merge", {
  a = loro_doc(peer_id = 1)
  body = loro_text()
  map_set(doc_map(a, "root"), body = body)
  text_insert(body, 1, "Hello")

  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))
  body_b = map_get(doc_map(b, "root"), "body")
  expect_s3_class(body_b, "creditor::loro_text")
  expect_identical(container_id(body_b), container_id(body))

  text_insert(body, 6, " world")
  text_insert(body_b, 1, ">> ")
  map_set(doc_map(b, "root"), seen = TRUE)

  doc_import(b, doc_export_updates(a, from = doc_version(b)))
  doc_import(a, doc_export_updates(b, from = doc_version(a)))

  expect_identical(text_get(body), ">> Hello world")
  expect_identical(doc_value(a), doc_value(b))
  expect_identical(map_get(doc_map(a, "root"), "seen"), TRUE)
})

test_that("handles are type checked", {
  doc = loro_doc()
  expect_error(container_value(doc), "loro_container")
  expect_error(container_id("x"), "loro_container")
  expect_error(map_set(doc_text(doc), k = 1), "loro_map")
  expect_error(list_push(doc_map(doc), 1), "loro_list")
  expect_error(doc_map(doc, 1), "name")
})

test_that("containers print their id and contents", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "hi")
  header = NULL
  contents = utils::capture.output({
    header = cli::cli_fmt(print(text))
  })
  expect_match(header[1], "loro_text")
  expect_match(header[1], "cid:root-text:Text", fixed = TRUE)
  expect_match(contents, "hi")
})

test_that("a handle reports when its container has been deleted", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  child = loro_text()
  map_set(map, c = child)
  text_insert(child, 1, "x")
  expect_false(container_is_deleted(child))
  expect_false(container_is_deleted(map))

  map_set(map, c = 1L)
  expect_true(container_is_deleted(child))
  expect_identical(text_get(child), "x")
  expect_error(text_insert(child, 1, "y"), "deleted")

  items = doc_list(doc, "l")
  nested = loro_map()
  list_push(items, nested)
  list_clear(items)
  expect_true(container_is_deleted(nested))
  expect_error(container_is_deleted(doc), "loro_container")
})

test_that("a shallow value shows child containers by id", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  map_set(map, v = 1L)
  text = loro_text()
  map_set(map, t = text)
  text_insert(text, 1, "hi")
  items = doc_list(doc, "l")
  list_push(items, "a")
  counter = loro_counter()
  list_push(items, counter)

  expect_identical(container_value(map, deep = FALSE), list(t = container_id(text), v = 1L))
  expect_identical(container_value(map), list(t = "hi", v = 1L))
  expect_identical(container_value(items, deep = FALSE), list("a", container_id(counter)))
  expect_identical(container_value(text, deep = FALSE), "hi")
  expect_error(container_value(map, deep = NA), "deep")
})

test_that("every child type can be created under every parent type", {
  types = c("text", "map", "list", "movable_list", "counter", "tree")
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  plain = doc_list(doc, "l")
  movable = doc_movable_list(doc, "ml")

  for (type in types) {
    class = paste0("creditor::loro_", type)
    new = get(paste0("loro_", type))
    in_map = new()
    map[[type]] = in_map
    in_list = new()
    list_push(plain, in_list)
    list_push(movable, "placeholder")
    in_movable = new()
    list_set(movable, list_length(movable), in_movable)

    expect_s3_class(in_map, class)
    expect_s3_class(in_list, class)
    expect_s3_class(in_movable, class)
    expect_identical(container_id(map_get(map, type)), container_id(in_map))
    expect_identical(container_id(list_get(plain, list_length(plain))), container_id(in_list))
    expect_identical(
      container_id(list_get(movable, list_length(movable))),
      container_id(in_movable)
    )
  }

  copy = loro_doc()
  doc_import(copy, doc_export(doc))
  expect_identical(doc_value(copy), doc_value(doc))
})

test_that("edits through any handle to a deleted container are errors", {
  doc = loro_doc()
  root = doc_map(doc, "root")
  parent = loro_map()
  map_set(root, parent = parent)
  child_map = loro_map()
  map_set(parent, map = child_map)
  child_list = loro_list()
  map_set(parent, list = child_list)
  child_movable = loro_movable_list()
  map_set(parent, movable = child_movable)
  child_counter = loro_counter()
  map_set(parent, counter = child_counter)
  child_tree = loro_tree()
  map_set(parent, tree = child_tree)
  list_push(child_list, "x")
  list_push(child_movable, "x")
  map_set(child_map, k = 1L)

  map_delete(root, "parent")
  for (handle in list(parent, child_map, child_list, child_movable, child_counter, child_tree)) {
    expect_true(container_is_deleted(handle))
  }

  expect_error(map_set(child_map, k = 2L), "deleted")
  expect_error(map_set(child_map, c = loro_text()), "deleted")
  expect_error(map_delete(child_map, "k"), "deleted")
  expect_error(map_clear(child_map), "deleted")
  expect_error(list_push(child_list, "y"), "deleted")
  expect_error(list_delete(child_list, 1), "deleted")
  expect_error(list_pop(child_list), "deleted")
  expect_error(list_clear(child_list), "deleted")
  expect_error(list_set(child_movable, 1, "y"), "deleted")
  expect_error(counter_increment(child_counter), "deleted")
  expect_error(tree_create(child_tree), "deleted")

  expect_identical(map_get(child_map, "k"), 1L)
  expect_identical(container_value(child_list), list("x"))
})

test_that("replacing or clearing a parent marks its children deleted", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  in_map = loro_text()
  map_set(map, a = in_map)
  map_clear(map)
  expect_true(container_is_deleted(in_map))

  movable = doc_movable_list(doc, "ml")
  first = loro_text()
  list_push(movable, first)
  list_set(movable, 1, "plain")
  expect_true(container_is_deleted(first))
  second = loro_map()
  list_set(movable, 1, second)
  list_set(movable, 1, loro_text())
  expect_true(container_is_deleted(second))
})

test_that("root containers of different types can share a name", {
  doc = loro_doc(peer_id = 1)
  items = doc_list(doc, "x")
  list_push(items, "item")
  map = doc_map(doc, "x")
  map_set(map, k = 1L)

  expect_identical(container_value(items), list("item"))
  expect_identical(container_value(map), list(k = 1L))
  expect_false(identical(container_id(items), container_id(map)))
  expect_length(doc_value(doc), 1)
  expect_named(doc_value(doc), "x")
})
