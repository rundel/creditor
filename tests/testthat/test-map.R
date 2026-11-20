test_that("values can be set, read, and deleted", {
  map = doc_map(loro_doc())
  expect_identical(map_length(map), 0L)
  expect_identical(map_keys(map), character())
  expect_null(map_get(map, "missing"))

  map_set(map, b = 2)
  map_set(map, a = "one")
  expect_identical(map_keys(map), c("a", "b"))
  expect_identical(map_length(map), 2L)
  expect_identical(map_get(map, "a"), "one")

  map_set(map, a = "uno")
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
    map[[key]] = values[[key]]
  }
  expect_identical(container_value(map), values[order(names(values))])
})

test_that("NULL and NA are stored as null", {
  map = doc_map(loro_doc())
  map_set(map, null = NULL)
  map_set(map, na = NA)
  map_set(map, na_chr = NA_character_)
  expect_identical(map_keys(map), c("na", "na_chr", "null"))
  expect_null(map_get(map, "na"))
  expect_null(map_get(map, "na_chr"))
})

test_that("vectors and lists become lists and maps", {
  map = doc_map(loro_doc())

  map_set(map, vec = c(1L, NA, 3L))
  expect_identical(map_get(map, "vec"), list(1L, NULL, 3L))

  map_set(map, empty = character())
  expect_identical(map_get(map, "empty"), list())

  map_set(map, named = c(b = "x", a = "y"))
  expect_identical(map_get(map, "named"), list(a = "y", b = "x"))

  map_set(map, nested = list(x = list(1, "two"), y = list(z = TRUE)))
  expect_identical(
    map_get(map, "nested"),
    list(x = list(1, "two"), y = list(z = TRUE))
  )

  map_set(map, one = list(1))
  expect_identical(map_get(map, "one"), list(1))
})

test_that("unsupported values are errors", {
  map = doc_map(loro_doc())
  expect_error(map_set(map, f = factor("a")), "class")
  expect_error(map_set(map, d = Sys.Date()), "class")
  expect_error(map_set(map, fn = mean))
  expect_error(map_set(map, partial = list(a = 1, 2)), "names")
  expect_error(map_set(map, dup = list(a = 1, a = 2)), "unique")
  expect_error(map_set(map, 1), "named")
  expect_error(map_set(map, a = 1, 2), "named")
  expect_error(map_set(map, a = 1, a = 2), "unique")
  expect_error(map_get(map, NA_character_), "key")
  expect_error(map[[NA_character_]] <- 1, "single string")
  expect_identical(map_length(map), 0L)
})

test_that("child containers can be created and retrieved", {
  map = doc_map(loro_doc())
  text = map_set_container(map, "text", "text")
  inner = map_set_container(map, "map", "map")
  list = map_set_container(map, "list", "list")

  text_insert(text, 1, "abc")
  map_set(inner, k = 1L)
  list_push(list, "x")

  expect_identical(text_get(map_get(map, "text")), "abc")
  expect_identical(map_get(map_get(map, "map"), "k"), 1L)
  expect_identical(list_get(map_get(map, "list"), 1), "x")
  expect_error(map_set_container(map, "bad", "nope"), "type")
})

test_that("concurrent writes to one key converge", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  map_set(doc_map(a), k = "from a")
  map_set(doc_map(b), k = "from b")
  map_set(doc_map(b), other = 1L)

  doc_import(b, doc_export_updates(a))
  doc_import(a, doc_export_updates(b))

  expect_identical(doc_value(a), doc_value(b))
  expect_true(map_get(doc_map(a), "k") %in% c("from a", "from b"))
  expect_identical(map_get(doc_map(a), "other"), 1L)
})

test_that("a map can be cleared", {
  map = doc_map(loro_doc())
  map_set(map, a = 1L)
  map_set_container(map, "b", "text")
  map_clear(map)
  expect_identical(map_keys(map), character())
  expect_identical(map_length(map), 0L)
})

test_that("the last editor of a key is reported", {
  a = loro_doc(peer_id = 1)
  map = doc_map(a)
  expect_identical(map_last_editor(map, "k"), NA_character_)
  map_set(map, k = 1L)
  expect_identical(map_last_editor(map, "k"), "1")

  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))
  map_set(doc_map(b), k = 2L)
  doc_import(a, doc_export_updates(b))
  expect_identical(map_last_editor(map, "k"), "2")
})

test_that("an ensured container is created once and then reused", {
  map = doc_map(loro_doc(peer_id = 1), "m")
  body = map_ensure_container(map, "body", "text")
  expect_s3_class(body, "creditor::loro_text")
  text_insert(body, 1, "x")

  again = map_ensure_container(map, "body", "text")
  expect_identical(container_id(again), container_id(body))
  expect_identical(text_get(again), "x")

  for (type in c("map", "list", "movable_list", "counter", "tree")) {
    child = map_ensure_container(map, paste0("c_", type), type)
    expect_s3_class(child, paste0("creditor::loro_", type))
  }
})

test_that("ensured containers created concurrently merge into one", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  text_insert(map_ensure_container(doc_map(a, "m"), "body", "text"), 1, "from a ")
  text_insert(map_ensure_container(doc_map(b, "m"), "body", "text"), 1, "from b ")

  doc_import(a, doc_export_updates(b))
  doc_import(b, doc_export_updates(a))
  expect_identical(doc_value(a), doc_value(b))
  body = doc_value(a)$m$body
  expect_match(body, "from a ", fixed = TRUE)
  expect_match(body, "from b ", fixed = TRUE)
})

test_that("containers set concurrently do not merge", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  text_insert(map_set_container(doc_map(a, "m"), "body", "text"), 1, "from a ")
  text_insert(map_set_container(doc_map(b, "m"), "body", "text"), 1, "from b ")

  doc_import(a, doc_export_updates(b))
  doc_import(b, doc_export_updates(a))
  expect_identical(doc_value(a), doc_value(b))
  expect_true(doc_value(a)$m$body %in% c("from a ", "from b "))
})

test_that("ensuring a container over a conflicting entry is an error", {
  map = doc_map(loro_doc(), "m")
  map_set(map, plain = 1L)
  map_ensure_container(map, "body", "text")
  map_set_container(map, "regular", "text")

  expect_error(map_ensure_container(map, "plain", "text"), "non-mergeable")
  expect_error(map_ensure_container(map, "body", "list"), "text container")
  expect_error(map_ensure_container(map, "regular", "text"))
  expect_error(map_ensure_container(map, "new", "nope"), "type")
  expect_s3_class(map_get(map, "body"), "creditor::loro_text")
})

test_that("several keys are set at once, in order", {
  map = doc_map(loro_doc())
  expect_identical(map_set(map, a = 1L, b = "two", c = NULL), map)
  expect_identical(map_keys(map), c("a", "b", "c"))
  expect_identical(map_set(map), map)

  values = list(d = 4L, e = 5L)
  key = "f"
  map_set(map, !!!values, "{key}" := 6L)
  expect_identical(map_get(map, "e"), 5L)
  expect_identical(map_get(map, "f"), 6L)

  expect_error(map_set(map, g = 7L, h = factor("x")), "class")
  expect_identical(map_get(map, "g"), 7L)
})

test_that("keys can be tested for and deleted together", {
  map = doc_map(loro_doc())
  map_set(map, a = 1L, b = NULL, c = 3L)
  expect_identical(map_has(map, c("a", "b", "z")), c(TRUE, TRUE, FALSE))
  expect_identical(map_has(map, character()), logical())
  map_delete(map, c("a", "b"))
  expect_identical(map_keys(map), "c")
  map_delete(map, character())
  map_delete(map)
  expect_identical(map_keys(map), "c")
  map_set(map, d = 1, e = 2, f = 3)
  map_delete(map, "c", c("d", "e"))
  expect_identical(map_keys(map), "f")
  expect_error(map_delete(map, 1), "keys")
  expect_error(map_delete(map, keys = "f"), "named")
  expect_error(map_has(map, NA_character_), "keys")
})

test_that("a map handle works with base accessors", {
  doc = loro_doc()
  map = doc_map(doc)
  map$title = "Notes"
  map[["a b"]] = 2L
  map[[""]] = "empty"
  expect_identical(map$title, "Notes")
  expect_identical(map[["a b"]], 2L)
  expect_identical(map[[""]], "empty")
  expect_null(map$missing)
  expect_null(map$tit)
  expect_identical(names(map), c("", "a b", "title"))
  expect_identical(length(map), 3L)
  expect_identical(as.list(map), container_value(map))

  body = map_set_container(map, "body", "text")
  text_insert(body, 1, "Hello")
  expect_s3_class(map$body, "creditor::loro_text")
  expect_identical(text_get(map[["body"]]), "Hello")

  map_set(map, gone = 1L, also = 2L, null = NULL)
  map$title = NULL
  map[["gone"]] = NULL
  map$absent = NULL
  expect_identical(map_has(map, c("title", "gone", "absent", "null")), c(FALSE, FALSE, FALSE, TRUE))
  map_delete(map, "also", "null")
  expect_error(map[[1]], "single string")
  expect_error(map$f <- factor("a"), "class")
  expect_identical(doc_value(doc)$map$`a b`, 2L)
})

test_that("assignment reaches through child containers", {
  doc = loro_doc()
  root = doc_map(doc, "root")
  child = map_set_container(root, "child", "map")
  items = map_set_container(child, "items", "movable_list")
  list_push(items, "a")
  id = container_id(child)

  root$child$done = TRUE
  root[["child"]][["label"]] = "x"
  root$child$items[[1]] = "b"
  expect_identical(as.list(root), list(child = list(done = TRUE, items = list("b"), label = "x")))
  expect_identical(container_id(root$child), id)

  other = doc_map(doc, "other")
  expect_error(root$child <- other, "cannot be stored")
  expect_error(root$new <- other, "cannot be stored")
  expect_error(items[[1]] <- other, "cannot be stored")
  expect_error(map_set(root, k = other), "class")
})
