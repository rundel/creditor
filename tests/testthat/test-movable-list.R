test_that("a movable list supports the plain list functions", {
  doc = loro_doc()
  items = doc_movable_list(doc, "l")
  expect_s3_class(items, "creditor::loro_movable_list")
  expect_identical(container_id(items), "cid:root-l:MovableList")

  list_push(items, "b")
  list_insert(items, 1, "a")
  list_push(items, "c")
  expect_identical(list_length(items), 3L)
  expect_identical(list_get(items, 2), "b")

  list_delete(items, 2)
  expect_identical(container_value(items), list("a", "c"))
  expect_identical(doc_value(doc), list(l = list("a", "c")))
})

test_that("elements can be moved", {
  items = doc_movable_list(loro_doc())
  for (x in c("a", "b", "c", "d")) list_push(items, x)

  list_move(items, 4, 1)
  expect_identical(container_value(items), list("d", "a", "b", "c"))
  list_move(items, 1, 3)
  expect_identical(container_value(items), list("a", "b", "d", "c"))
  list_move(items, 2, 2)
  expect_identical(container_value(items), list("a", "b", "d", "c"))
})

test_that("elements can be set in place", {
  items = doc_movable_list(loro_doc())
  list_push(items, "a")
  list_push(items, "b")

  list_set(items, 2, list(x = 1L))
  expect_identical(container_value(items), list("a", list(x = 1L)))

  text = list_set_container(items, 1, "text")
  text_insert(text, 1, "hi")
  expect_identical(text_get(list_get(items, 1)), "hi")
  expect_identical(list_length(items), 2L)
})

test_that("concurrent moves of one element leave a single copy", {
  a = loro_doc(peer_id = 1)
  items = doc_movable_list(a)
  for (x in c("a", "b", "c")) list_push(items, x)
  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))

  list_move(items, 1, 3)
  list_move(doc_movable_list(b), 1, 2)
  doc_import(b, doc_export(a, "updates"))
  doc_import(a, doc_export(b, "updates"))

  expect_identical(doc_value(a), doc_value(b))
  expect_setequal(unlist(container_value(items)), c("a", "b", "c"))
  expect_identical(list_length(items), 3L)
})

test_that("concurrent sets resolve to one value", {
  a = loro_doc(peer_id = 1)
  list_push(doc_movable_list(a), "start")
  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))

  list_set(doc_movable_list(a), 1, "from a")
  list_set(doc_movable_list(b), 1, "from b")
  doc_import(b, doc_export(a, "updates"))
  doc_import(a, doc_export(b, "updates"))

  expect_identical(doc_value(a), doc_value(b))
  expect_identical(list_length(doc_movable_list(a)), 1L)
})

test_that("move and set need a movable list and valid positions", {
  doc = loro_doc()
  plain = doc_list(doc, "plain")
  list_push(plain, 1)
  expect_error(list_move(plain, 1, 1), "loro_movable_list")
  expect_error(list_set(plain, 1, 2), "loro_movable_list")
  expect_error(list_set_container(plain, 1, "text"), "loro_movable_list")

  items = doc_movable_list(doc, "items")
  list_push(items, 1)
  expect_error(list_move(items, 0, 1), "from")
  expect_error(list_move(items, 1, 5))
  expect_error(list_set(items, 3, 1))
  expect_error(list_set_container(items, 1, "nope"), "type")
})

test_that("movable lists nest and appear in diffs as lists", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  items = map_set_container(map, "items", "movable_list")
  expect_s3_class(items, "creditor::loro_movable_list")
  list_push(items, "a")
  v1 = doc_frontiers(doc)

  list_push(items, "b")
  diff = doc_diff(doc, v1, doc_frontiers(doc))
  expect_identical(
    diff[[container_id(items)]],
    list(type = "list", delta = list(list(retain = 1L), list(insert = list("b"))))
  )
  expect_s3_class(map_get(map, "items"), "creditor::loro_movable_list")
})
