long_history = function(n = 200) {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  for (i in seq_len(n)) {
    text_insert(text, 1, "abcdefghij")
    text_delete(text, 1, 9)
    doc_commit(doc, paste("change", i))
  }
  doc
}

empty_range = data.frame(peer = character(), start = integer(), end = integer())

test_that("import reports the operations it applied", {
  a = loro_doc(peer_id = 1)
  text_insert(doc_text(a), 1, "Hello")
  b = loro_doc()

  status = doc_import(b, doc_export(a))
  expect_identical(status$success, data.frame(peer = "1", start = 0L, end = 5L))
  expect_identical(status$pending, empty_range)
  expect_invisible(doc_import(b, doc_export(a)))
})

test_that("updates that arrive early are pending until their dependencies do", {
  a = loro_doc(peer_id = 5)
  text = doc_text(a)
  text_insert(text, 1, "a")
  doc_commit(a)
  version = doc_version(a)
  first = doc_export(a, "updates")
  text_insert(text, 2, "b")
  doc_commit(a)
  second = doc_export(a, "updates", from = version)

  b = loro_doc()
  status = doc_import(b, second)
  expect_identical(status$success, empty_range)
  expect_identical(status$pending, data.frame(peer = "5", start = 1L, end = 2L))
  expect_identical(text_get(doc_text(b)), "")

  status = doc_import(b, first)
  expect_identical(status$success, data.frame(peer = "5", start = 0L, end = 2L))
  expect_identical(status$pending, empty_range)
  expect_identical(text_get(doc_text(b)), "ab")
})

test_that("a list of updates is imported together in any order", {
  a = loro_doc(peer_id = 5)
  text = doc_text(a)
  text_insert(text, 1, "a")
  doc_commit(a)
  version = doc_version(a)
  first = doc_export(a, "updates")
  text_insert(text, 2, "b")
  second = doc_export(a, "updates", from = version)

  b = loro_doc()
  status = doc_import(b, list(second, first))
  expect_identical(status$pending, empty_range)
  expect_identical(text_get(doc_text(b)), "ab")

  expect_identical(doc_import(b, list())$success, empty_range)
  expect_error(doc_import(b, list(first, "x")), "raw")
})

test_that("a shallow snapshot keeps contents but drops old history", {
  doc = long_history()
  full = doc_export(doc)
  shallow = doc_export(doc, "shallow_snapshot")
  expect_lt(length(shallow), length(full) / 2)

  copy = loro_doc()
  doc_import(copy, shallow)
  expect_true(doc_is_shallow(copy))
  expect_false(doc_is_shallow(doc))
  expect_identical(doc_value(copy), doc_value(doc))
  expect_lt(nrow(doc_changes(copy)), nrow(doc_changes(doc)))
})

test_that("a shallow snapshot keeps history after `since`", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  text_insert(text, 1, "one")
  doc_commit(doc, "one")
  v1 = doc_frontiers(doc)
  text_insert(text, 4, " two")
  doc_commit(doc, "two")
  v2 = doc_frontiers(doc)
  text_insert(text, 8, " three")
  doc_commit(doc, "three")

  copy = loro_doc()
  doc_import(copy, doc_export(doc, "shallow_snapshot", since = v2))
  expect_identical(text_get(doc_text(copy)), "one two three")
  expect_identical(doc_changes(copy)$message, c("two", "three"))

  doc_checkout(copy, v2)
  expect_identical(text_get(doc_text(copy)), "one two")
  expect_error(doc_checkout(copy, v1), "shallow")
  doc_checkout(copy)

  text_insert(doc_text(copy), 1, "> ")
  doc_import(doc, doc_export(copy, "updates"))
  expect_identical(text_get(text), "> one two three")
  expect_error(doc_export(doc, "shallow_snapshot", since = "v2"), "since")
})

test_that("blob metadata describes an export", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  version = doc_version(doc)
  text_insert(doc_text(doc), 2, "b")
  doc_commit(doc, "second")

  meta = blob_metadata(doc_export(doc))
  expect_named(
    meta,
    c(
      "mode", "changes", "start_timestamp", "end_timestamp",
      "start_frontiers", "start_version", "end_version"
    )
  )
  expect_identical(meta$mode, "snapshot")
  expect_identical(meta$changes, 2L)
  expect_s3_class(meta$end_timestamp, "POSIXct")
  expect_identical(meta$end_version, doc_version(doc))

  updates = blob_metadata(doc_export(doc, "updates", from = version))
  expect_identical(updates$mode, "update")
  expect_identical(updates$start_version, version)
  expect_identical(blob_metadata(doc_export(doc, "shallow_snapshot"))$mode, "shallow-snapshot")

  expect_error(blob_metadata(as.raw(1:30)))
  expect_error(blob_metadata("x"), "raw")
})

test_that("changes round trip through JSON", {
  a = loro_doc(peer_id = 5)
  text_insert(doc_text(a), 1, "Hello")
  map_set(doc_map(a, "m"), "k", list(1L, "two"))
  doc_commit(a, "first")
  version = doc_version(a)

  json = doc_export_json(a)
  expect_type(json, "character")
  expect_length(json, 1)
  expect_match(json, "schema_version", fixed = TRUE)
  expect_match(json, "Hello")

  b = loro_doc()
  status = doc_import_json(b, json)
  expect_identical(status$success$peer, "5")
  expect_identical(doc_value(b), doc_value(a))
  expect_identical(doc_changes(b)$message, "first")

  text_insert(doc_text(a), 6, "!")
  doc_import_json(b, doc_export_json(a, from = version))
  expect_identical(text_get(doc_text(b)), "Hello!")

  earlier = doc_export_json(a, to = version)
  expect_false(grepl("!", earlier, fixed = TRUE))
})

test_that("invalid JSON input is an error", {
  doc = loro_doc()
  expect_error(doc_import_json(doc, "{bad"), "not valid")
  expect_error(doc_import_json(doc, "[1, 2]"), "not valid")
  expect_error(doc_import_json(doc, 1), "json")
  expect_error(doc_export_json(doc, from = "x"), "from")
  expect_error(doc_export_json(doc, to = 1), "to")
})
