test_that("values can be set, read, and deleted", {
  map = doc_map(loro_doc())
  expect_identical(map_length(map), 0L)
  expect_identical(map_keys(map), character())
  expect_null(map_get(map, "missing"))

  map_set(map, "b", 2)
  map_set(map, "a", "one")
  expect_identical(map_keys(map), c("a", "b"))
  expect_identical(map_length(map), 2L)
  expect_identical(map_get(map, "a"), "one")

  map_set(map, "a", "uno")
  expect_identical(map_get(map, "a"), "uno")

  map_delete(map, "a")
  expect_identical(map_keys(map), "b")
  expect_null(map_get(map, "a"))
})

test_that("scalar values round trip with their types", {
  map = doc_map(loro_doc())
  values = list(
    lgl = TRUE,
    int = 3L,
    dbl = 2.5,
    whole_dbl = 4,
    chr = "héllo",
    raw = as.raw(c(1, 255)),
    big = 2^40
  )
  for (key in names(values)) {
    map_set(map, key, values[[key]])
  }
  expect_identical(container_value(map), values[order(names(values))])
})

test_that("NULL and NA are stored as null", {
  map = doc_map(loro_doc())
  map_set(map, "null", NULL)
  map_set(map, "na", NA)
  map_set(map, "na_chr", NA_character_)
  expect_identical(map_keys(map), c("na", "na_chr", "null"))
  expect_null(map_get(map, "na"))
  expect_null(map_get(map, "na_chr"))
})

test_that("vectors and lists become lists and maps", {
  map = doc_map(loro_doc())

  map_set(map, "vec", c(1L, NA, 3L))
  expect_identical(map_get(map, "vec"), list(1L, NULL, 3L))

  map_set(map, "empty", character())
  expect_identical(map_get(map, "empty"), list())

  map_set(map, "named", c(b = "x", a = "y"))
  expect_identical(map_get(map, "named"), list(a = "y", b = "x"))

  map_set(map, "nested", list(x = list(1, "two"), y = list(z = TRUE)))
  expect_identical(
    map_get(map, "nested"),
    list(x = list(1, "two"), y = list(z = TRUE))
  )

  map_set(map, "one", list(1))
  expect_identical(map_get(map, "one"), list(1))
})

test_that("unsupported values are errors", {
  map = doc_map(loro_doc())
  expect_error(map_set(map, "f", factor("a")), "class")
  expect_error(map_set(map, "d", Sys.Date()), "class")
  expect_error(map_set(map, "fn", mean))
  expect_error(map_set(map, "partial", list(a = 1, 2)), "names")
  expect_error(map_set(map, "dup", list(a = 1, a = 2)), "unique")
  expect_error(map_set(map, NA_character_, 1), "key")
  expect_identical(map_length(map), 0L)
})

test_that("child containers can be created and retrieved", {
  map = doc_map(loro_doc())
  text = map_set_container(map, "text", "text")
  inner = map_set_container(map, "map", "map")
  list = map_set_container(map, "list", "list")

  text_insert(text, 1, "abc")
  map_set(inner, "k", 1L)
  list_push(list, "x")

  expect_identical(text_get(map_get(map, "text")), "abc")
  expect_identical(map_get(map_get(map, "map"), "k"), 1L)
  expect_identical(list_get(map_get(map, "list"), 1), "x")
  expect_error(map_set_container(map, "bad", "tree"), "type")
})

test_that("concurrent writes to one key converge", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  map_set(doc_map(a), "k", "from a")
  map_set(doc_map(b), "k", "from b")
  map_set(doc_map(b), "other", 1L)

  doc_import(b, doc_export(a, "updates"))
  doc_import(a, doc_export(b, "updates"))

  expect_identical(doc_value(a), doc_value(b))
  expect_true(map_get(doc_map(a), "k") %in% c("from a", "from b"))
  expect_identical(map_get(doc_map(a), "other"), 1L)
})
