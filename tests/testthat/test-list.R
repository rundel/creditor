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

  list_delete(list, 1:2)
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
  text = loro_text()
  list_insert(list, 1, text)
  map = loro_map()
  list_push(list, map)

  text_insert(text, 1, "abc")
  map_set(map, k = TRUE)

  expect_identical(text_get(list_get(list, 1)), "abc")
  expect_identical(list_get(list, 2), "plain")
  expect_identical(map_get(list_get(list, 3), "k"), TRUE)
  expect_identical(container_value(list), list("abc", "plain", list(k = TRUE)))
})

test_that("out of range positions are errors", {
  list = doc_list(loro_doc())
  list_push(list, 1)
  expect_error(list_get(list, 2), "at most 1")
  expect_error(list_get(list, 0), "pos")
  expect_error(list_insert(list, 3, "x"))
  expect_error(list_delete(list, 1:5))
  expect_identical(list_length(list), 1L)
})

test_that("concurrent insertions are all kept", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  list_push(doc_list(a), "from a")
  list_push(doc_list(b), "from b")

  doc_import(b, doc_export_updates(a))
  doc_import(a, doc_export_updates(b))

  expect_identical(doc_value(a), doc_value(b))
  expect_setequal(unlist(container_value(doc_list(a))), c("from a", "from b"))
})

test_that("elements can be popped and the list cleared", {
  for (make in list(doc_list, doc_movable_list)) {
    items = make(loro_doc())
    expect_null(list_pop(items))

    list_push(items, 1L)
    list_push(items, "two")
    child = loro_text()
    list_push(items, child)
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

test_that("out of range errors name the 1-based position given", {
  for (make in list(doc_list, doc_movable_list)) {
    items = make(loro_doc())
    list_push(items, "a")
    list_push(items, "b")

    expect_error(list_insert(items, 4, "c"), "at most 3.*not 4")
    expect_error(list_insert(items, 4, loro_text()), "at most 3.*not 4")
    expect_error(list_get(items, 3), "at most 2.*not 3")
    expect_error(list_delete(items, 2:3), "at most 2.*not 3")
    expect_error(list_delete(items, 0), "whole numbers >= 1")
    expect_error(list_delete(items, c(1, 1)), "duplicates")
    expect_error(list_delete(items, c(1, NA)), "whole numbers")
    expect_error(list_delete(items, "1"), "whole numbers")

    list_delete(items, integer())
    list_insert(items, 3, "c")
    expect_identical(container_value(items), list("a", "b", "c"))
  }
})

test_that("range arithmetic does not overflow", {
  items = doc_list(loro_doc())
  list_push(items, "a")
  expect_error(list_delete(items, 1:(.Machine$integer.max)), "positions")
  expect_error(list_delete(items, .Machine$integer.max + 1), "at most 1")
  expect_identical(list_length(items), 1L)
})

test_that("several values are added at once", {
  for (make in list(doc_list, doc_movable_list)) {
    items = make(loro_doc())
    list_push(items, "c", "d")
    list_insert(items, 1, "a", "b")
    list_insert(items, 5, "e", list(k = 1L), c(1L, 2L))
    list_push(items)
    list_push(items, !!!list("y", "z"))
    expect_identical(
      as.list(items),
      list("a", "b", "c", "d", "e", list(k = 1L), list(1L, 2L), "y", "z")
    )
    expect_error(list_push(items, k = 1L), "must not be named")
    expect_error(list_insert(items, 1, k = 1L), "must not be named")
    expect_identical(length(items), 9L)
  }
})

test_that("any set of positions can be deleted", {
  items = doc_list(loro_doc())
  list_push(items, !!!as.list(letters[1:8]))
  list_delete(items, c(8, 1, 4, 3))
  expect_identical(as.list(items), list("b", "e", "f", "g"))
  list_delete(items, 2:3)
  expect_identical(as.list(items), list("b", "g"))
})

test_that("a list handle works with base accessors", {
  doc = loro_doc()
  items = doc_list(doc, "plain")
  list_push(items, "a", "b")
  expect_identical(items[[2]], "b")
  expect_identical(length(items), 2L)
  expect_error(items[[3]], "at most 2")
  expect_error(items[[1]] <- "z", "loro_movable_list")
  items[[1]] = NULL
  expect_identical(as.list(items), list("b"))

  movable = doc_movable_list(doc, "movable")
  list_push(movable, "a", "b")
  movable[[1]] = "z"
  expect_identical(as.list(movable), list("z", "b"))
})
