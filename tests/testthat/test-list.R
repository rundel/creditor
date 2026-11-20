test_that("values can be inserted, read, and deleted", {
  list = doc_list(loro_doc())
  expect_identical(list_length(list), 0L)

  list_push(list, "b")
  list_push(list, "c")
  list_insert(list, 1, "a")
  expect_identical(container_value(list), list("a", "b", "c"))
  expect_identical(list_length(list), 3L)
  expect_identical(list_get(list, 2), "b")

  list_delete(list, 2)
  expect_identical(container_value(list), list("a", "c"))

  list_delete(list, 1, 2)
  expect_identical(container_value(list), list())
})

test_that("a vector is inserted as a single element", {
  list = doc_list(loro_doc())
  list_push(list, c(1, 2))
  expect_identical(list_length(list), 1L)
  expect_identical(list_get(list, 1), list(1, 2))
})

test_that("child containers can be created and retrieved", {
  list = doc_list(loro_doc())
  list_push(list, "plain")
  text = list_insert_container(list, 1, "text")
  map = list_push_container(list, "map")

  text_insert(text, 1, "abc")
  map_set(map, "k", TRUE)

  expect_identical(text_get(list_get(list, 1)), "abc")
  expect_identical(list_get(list, 2), "plain")
  expect_identical(map_get(list_get(list, 3), "k"), TRUE)
  expect_identical(container_value(list), list("abc", "plain", list(k = TRUE)))
})

test_that("out of range positions are errors", {
  list = doc_list(loro_doc())
  list_push(list, 1)
  expect_error(list_get(list, 2), "bounds")
  expect_error(list_get(list, 0), "pos")
  expect_error(list_insert(list, 3, "x"))
  expect_error(list_delete(list, 1, 5))
  expect_error(list_insert_container(list, 1, "nope"), "type")
  expect_identical(list_length(list), 1L)
})

test_that("concurrent insertions are all kept", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  list_push(doc_list(a), "from a")
  list_push(doc_list(b), "from b")

  doc_import(b, doc_export(a, "updates"))
  doc_import(a, doc_export(b, "updates"))

  expect_identical(doc_value(a), doc_value(b))
  expect_setequal(unlist(container_value(doc_list(a))), c("from a", "from b"))
})

test_that("elements can be popped and the list cleared", {
  for (make in list(doc_list, doc_movable_list)) {
    items = make(loro_doc())
    expect_null(list_pop(items))

    list_push(items, 1L)
    list_push(items, "two")
    child = list_push_container(items, "text")
    text_insert(child, 1, "kid")

    expect_identical(list_pop(items), "kid")
    expect_identical(list_pop(items), "two")
    expect_identical(list_length(items), 1L)

    list_push(items, 3L)
    list_clear(items)
    expect_identical(list_length(items), 0L)
    list_clear(items)
    expect_identical(container_value(items), list())
  }
})
