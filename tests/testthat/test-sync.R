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

empty_range = tibble::tibble(peer = character(), start = integer(), end = integer())

test_that("import reports the operations it applied", {
  a = loro_doc(peer_id = 1)
  text_insert(doc_text(a), 1, "Hello")
  b = loro_doc()

  doc_import(b, doc_export(a))

  status = doc_import_status(b)
  expect_identical(status$success, tibble::tibble(peer = "1", start = 0L, end = 5L))
  expect_identical(status$pending, empty_range)
  expect_invisible(doc_import(b, doc_export(a)))
})

test_that("export_updates takes a document as the version to start from", {
  a = loro_doc(peer_id = 1)
  text_insert(a, 1, "Hello")
  b = loro_doc(peer_id = 2) |>
    doc_import(doc_export(a))
  text_push(a, " world")

  expect_identical(
    doc_export_updates(a, from = b),
    doc_export_updates(a, from = doc_version(b))
  )
})

test_that("merge imports only the changes the document is missing", {
  a = loro_doc(peer_id = 1)
  text_insert(a, 1, "Hello")
  b = loro_doc(peer_id = 2) |>
    doc_import(doc_export(a))
  text_push(a, " world")
  text_insert(b, 1, ">> ")

  expect_invisible(doc_merge(b, a))
  expect_identical(doc_merge(b, a), b)
  doc_merge(a, b)
  expect_identical(text_get(a), ">> Hello world")
  expect_identical(text_get(b), ">> Hello world")
  expect_identical(doc_import_status(a)$success, tibble::tibble(peer = "2", start = 0L, end = 3L))
})

test_that("merge checks its arguments", {
  doc = loro_doc()
  expect_error(doc_merge(doc, doc_export(doc)), "`source` must be a <loro_doc>")
  expect_error(doc_merge("x", doc), "`doc` must be a <loro_doc>")
})

test_that("updates that arrive early are pending until their dependencies do", {
  a = loro_doc(peer_id = 5)
  text = doc_text(a)
  text_insert(text, 1, "a")
  doc_commit(a)
  version = doc_version(a)
  first = doc_export_updates(a)
  text_insert(text, 2, "b")
  doc_commit(a)
  second = doc_export_updates(a, from = version)

  b = loro_doc()
  doc_import(b, second)
  status = doc_import_status(b)
  expect_identical(status$success, empty_range)
  expect_identical(status$pending, tibble::tibble(peer = "5", start = 1L, end = 2L))
  expect_identical(text_get(doc_text(b)), "")

  doc_import(b, first)

  status = doc_import_status(b)
  expect_identical(status$success, tibble::tibble(peer = "5", start = 0L, end = 2L))
  expect_identical(status$pending, empty_range)
  expect_identical(text_get(doc_text(b)), "ab")
})

test_that("a list of updates is imported together in any order", {
  a = loro_doc(peer_id = 5)
  text = doc_text(a)
  text_insert(text, 1, "a")
  doc_commit(a)
  version = doc_version(a)
  first = doc_export_updates(a)
  text_insert(text, 2, "b")
  second = doc_export_updates(a, from = version)

  b = loro_doc()
  doc_import(b, list(second, first))
  status = doc_import_status(b)
  expect_identical(status$pending, empty_range)
  expect_identical(text_get(doc_text(b)), "ab")

  expect_identical(doc_import_status(doc_import(b, list()))$success, empty_range)
  expect_error(doc_import(b, list(first, "x")), "raw")
})

test_that("a shallow snapshot keeps contents but drops old history", {
  doc = long_history()
  full = doc_export(doc)
  shallow = doc_export_shallow(doc)
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
  doc_import(copy, doc_export_shallow(doc, since = v2))
  expect_identical(text_get(doc_text(copy)), "one two three")
  expect_identical(doc_changes(copy)$message, c("two", "three"))

  doc_checkout(copy, v2)
  expect_identical(text_get(doc_text(copy)), "one two")
  expect_error(doc_checkout(copy, v1), "shallow")
  doc_checkout(copy)

  text_insert(doc_text(copy), 1, "> ")
  doc_import(doc, doc_export_updates(copy))
  expect_identical(text_get(text), "> one two three")
  expect_error(doc_export_shallow(doc, since = TRUE), "since")
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

  updates = blob_metadata(doc_export_updates(doc, from = version))
  expect_identical(updates$mode, "update")
  expect_identical(updates$start_version, version)
  expect_identical(blob_metadata(doc_export_shallow(doc))$mode, "shallow-snapshot")

  expect_error(blob_metadata(as.raw(1:30)))
  expect_error(blob_metadata("x"), "raw")
})

test_that("changes round trip through JSON", {
  a = loro_doc(peer_id = 5)
  text_insert(doc_text(a), 1, "Hello")
  map_set(doc_map(a, "m"), k = list(1L, "two"))
  doc_commit(a, "first")
  version = doc_version(a)

  json = doc_export_json(a)
  expect_type(json, "character")
  expect_length(json, 1)
  expect_match(json, "schema_version", fixed = TRUE)
  expect_match(json, "Hello")

  b = loro_doc()
  doc_import_json(b, json)
  status = doc_import_status(b)
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

test_that("damaged or foreign bytes are rejected without changing the document", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "abc")
  doc_commit(doc)
  value = doc_value(doc)
  version = doc_version(doc)
  snapshot = doc_export(doc)
  flipped = snapshot
  flipped[length(flipped) %/% 2] = xor(flipped[length(flipped) %/% 2], as.raw(0xff))

  for (bytes in list(raw(), as.raw(0:3), snapshot[1:(length(snapshot) %/% 2)], flipped)) {
    expect_error(doc_import(doc, bytes))
    expect_error(blob_metadata(bytes))
  }
  expect_error(doc_import(doc, list(snapshot, flipped)))

  expect_identical(doc_value(doc), value)
  expect_identical(doc_version(doc), version)
  expect_false(doc_is_detached(doc))
  text_insert(doc_text(doc), 1, "x")
  expect_identical(text_get(doc_text(doc)), "xabc")
})

test_that("malformed versions are clean errors in every function", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "abc")
  doc_commit(doc)
  empty = as_frontiers(raw())
  absent = as_frontiers(as.raw(c(1, 1, 1)))

  for (bad in list(empty, absent)) {
    expect_error(doc_checkout(doc, bad))
    expect_error(doc_fork(doc, at = bad))
    expect_error(doc_revert_to(doc, bad))
    expect_error(doc_diff(doc, bad, doc_frontiers(doc)))
    expect_error(doc_compare_frontiers(doc, bad, doc_frontiers(doc)))
    expect_error(doc_frontiers_to_version(doc, bad))
  }
  expect_error(doc_export_updates(doc, from = as_version(raw())), "Version vector")
  expect_error(doc_version_to_frontiers(doc, as_version(raw())), "Version vector")
  expect_error(doc_export_json(doc, from = as_version(raw())), "Version vector")

  expect_false(doc_is_detached(doc))
  text_insert(doc_text(doc), 1, "x")
  expect_identical(text_get(doc_text(doc)), "xabc")
})

test_that("each export function takes only its own kind of version", {
  doc = loro_doc()
  text_insert(doc_text(doc), 1, "a")
  expect_error(doc_export(doc, from = doc_version(doc)), "unused")
  expect_error(doc_export_updates(doc, from = doc_frontiers(doc)), "version vector")
  expect_error(doc_export_shallow(doc, since = doc_version(doc)), "frontiers")
})

test_that("importing known changes again reports nothing new", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "abc")
  version = doc_version(doc)

  doc_import(doc, doc_export(doc))

  status = doc_import_status(doc)
  expect_identical(nrow(status$success), 0L)
  expect_identical(nrow(status$pending), 0L)
  expect_identical(doc_version(doc), version)

  other = loro_doc()
  doc_import(other, doc_export(doc))
  doc_import(other, doc_export(doc))
  status = doc_import_status(other)
  expect_identical(nrow(status$success), 0L)
  doc_import_json(other, doc_export_json(doc))
  status = doc_import_status(other)
  expect_identical(nrow(status$success), 0L)
  expect_identical(text_get(doc_text(other)), "abc")
})

test_that("JSON updates that arrive early are pending", {
  doc = loro_doc(peer_id = 5)
  text = doc_text(doc)
  text_insert(text, 1, "abc")
  doc_commit(doc)
  version = doc_version(doc)
  text_insert(text, 4, "de")
  doc_commit(doc)

  other = loro_doc()
  doc_import_json(other, doc_export_json(doc, from = version))
  status = doc_import_status(other)
  expect_identical(status$pending, tibble::tibble(peer = "5", start = 3L, end = 5L))
  expect_identical(text_get(doc_text(other)), "")
  doc_import(other, doc_export_updates(doc))
  expect_identical(text_get(doc_text(other)), "abcde")
})

test_that("an invalid op in JSON is rejected without a source path in the message", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "xy")
  doc_commit(doc)
  value = doc_value(doc)
  json = paste0(
    '{"schema_version":1,"start_version":{},"peers":["9"],"changes":[{"id":"0@0",',
    '"timestamp":0,"deps":[],"lamport":0,"msg":null,"ops":[',
    '{"container":"cid:root-l:List","content":{"type":"insert","pos":5,"value":[1]},"counter":0}',
    ']}]}'
  )
  error = tryCatch(doc_import_json(doc, json), error = function(e) conditionMessage(e))
  expect_match(error, "retains 5 items")
  expect_false(grepl(".rs:", error, fixed = TRUE))
  expect_false(grepl("/", error, fixed = TRUE))
  expect_identical(doc_value(doc), value)
})

test_that("JSON cannot carry very deep values, and says so", {
  nested = 1L
  for (i in 1:200) nested = list(nested)
  doc = loro_doc()
  map_set(doc_map(doc, "m"), k = nested)

  other = loro_doc()
  expect_error(doc_import_json(other, doc_export_json(doc)), "120 levels")
  doc_import(other, doc_export(doc))
  expect_identical(doc_value(other), doc_value(doc))
})

test_that("a shallow document refuses history before its start, and stays usable", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  text_insert(text, 1, "abc")
  doc_commit(doc)
  v1 = doc_frontiers(doc)
  text_insert(text, 4, "de")
  doc_commit(doc)
  v2 = doc_frontiers(doc)
  text_insert(text, 6, "fg")
  doc_commit(doc)
  v3 = doc_frontiers(doc)

  shallow = loro_doc()
  doc_import(shallow, doc_export_shallow(doc, since = v2))
  expect_error(doc_diff(shallow, v1, v3), "shallow")
  expect_error(doc_revert_to(shallow, v1), "shallow")
  expect_error(doc_apply_diff(shallow, v1, v3), "shallow")
  expect_error(doc_fork(shallow, at = v3), "shallow document cannot be forked")
  expect_error(doc_change(shallow, "1", 0), "no change")

  expect_false(doc_is_detached(shallow))
  expect_true(doc_is_shallow(doc_fork(shallow)))
  text_insert(doc_text(shallow), 8, "!")
  expect_identical(text_get(doc_text(shallow)), "abcdefg!")
})

test_that("a deeply nested chain of containers is an error to read, not a crash", {
  depth = 1500
  ops = vapply(seq_len(depth), function(i) {
    container = if (i == 1) "cid:root-m:Map" else paste0("cid:", i - 2, "@0:Map")
    paste0(
      '{"container":"', container, '","content":{"type":"insert","key":"c","value":"\U0001F99C:cid:',
      i - 1, '@0:Map"},"counter":', i - 1, '}'
    )
  }, character(1))
  json = paste0(
    '{"schema_version":1,"start_version":{},"peers":["9"],"changes":[{"id":"0@0",',
    '"timestamp":0,"deps":[],"lamport":0,"msg":null,"ops":[', paste(ops, collapse = ","), ']}]}'
  )
  doc = loro_doc()
  doc_import_json(doc, json)

  expect_error(doc_value(doc), "1000 levels")
  expect_error(container_value(doc_map(doc, "m")), "1000 levels")
  shallow = container_value(doc_map(doc, "m"), deep = FALSE)
  expect_identical(shallow, list(c = "cid:0@9:Map"))
  expect_type(doc_export(doc), "raw")
})

test_that("JSON export refuses containers it cannot carry", {
  doc = loro_doc(peer_id = 1)
  items = map_ensure_container(doc_map(doc, "m"), "items", "list")
  list_push(items, "x")
  expect_error(doc_export_json(doc), "map_ensure_container")

  other = loro_doc()
  doc_import(other, doc_export(doc))
  expect_identical(doc_value(other), doc_value(doc))

  regular = loro_doc(peer_id = 1)
  map_set(doc_map(regular, "m"), items = loro_list("x"))
  copy = loro_doc()
  doc_import_json(copy, doc_export_json(regular))
  expect_identical(doc_value(copy), doc_value(regular))
})

test_that("imports return the document and keep their status with it", {
  a = loro_doc(peer_id = 1)
  text_insert(a, 1, "hi")
  b = loro_doc(peer_id = 2)
  expect_null(doc_import_status(b))

  out = withVisible(doc_import(b, doc_export(a)))
  expect_false(out$visible)
  expect_identical(container_id(doc_text(out$value)), container_id(doc_text(b)))
  expect_identical(loro_doc() |> doc_import(doc_export(a)) |> text_get(), "hi")

  status = doc_import_status(b)
  expect_named(status, c("success", "pending"))
  expect_identical(status$success$peer, "1")
  expect_identical(nrow(status$pending), 0L)

  json = doc_export_json(a)
  expect_identical(doc_import_json(b, json), b)
  expect_identical(nrow(doc_import_status(b)$success), 0L)
  expect_null(doc_import_status(doc_fork(b)))
})
