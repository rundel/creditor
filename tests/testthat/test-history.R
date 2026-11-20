history_doc = function() {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  text_insert(text, 1, "Hello")
  doc_commit(doc, "greeting")
  v1 = doc_frontiers(doc)
  text_insert(text, 6, " world")
  doc_commit(doc, "audience")
  v2 = doc_frontiers(doc)
  list(doc = doc, text = text, v1 = v1, v2 = v2)
}

test_that("frontiers identify versions", {
  doc = loro_doc(peer_id = 1)
  v0 = doc_frontiers(doc)
  expect_type(v0, "raw")

  text_insert(doc_text(doc), 1, "a")
  v1 = doc_frontiers(doc)
  expect_false(identical(v0, v1))
  expect_identical(doc_frontiers(doc), v1)
})

test_that("changes are listed with messages and frontiers", {
  h = history_doc()
  changes = doc_changes(h$doc)

  expect_s3_class(changes, "data.frame")
  expect_named(
    changes,
    c("peer", "counter", "lamport", "length", "timestamp", "message", "frontiers")
  )
  expect_identical(changes$peer, c("1", "1"))
  expect_identical(changes$counter, c(0L, 5L))
  expect_identical(changes$length, c(5L, 6L))
  expect_identical(changes$message, c("greeting", "audience"))
  expect_s3_class(changes$timestamp, "POSIXct")
  expect_true(all(is.na(changes$timestamp)))
  expect_identical(changes$frontiers, list(h$v1, h$v2))
})

test_that("an empty document has no changes", {
  changes = doc_changes(loro_doc())
  expect_identical(nrow(changes), 0L)
  expect_identical(ncol(changes), 7L)
})

test_that("changes from several peers are in causal order", {
  a = loro_doc(peer_id = 1)
  text_insert(doc_text(a), 1, "a")
  doc_commit(a, "first")
  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))
  text_insert(doc_text(b), 2, "b")
  doc_commit(b, "second")
  doc_import(a, doc_export(b, "updates"))

  changes = doc_changes(a)
  expect_identical(changes$peer, c("1", "2"))
  expect_identical(changes$message, c("first", "second"))
  expect_false(is.unsorted(changes$lamport))
})

test_that("timestamps are recorded on request", {
  doc = loro_doc()
  doc_record_timestamps(doc)
  before = Sys.time()
  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)

  timestamp = doc_changes(doc)$timestamp
  expect_false(is.na(timestamp))
  expect_lt(abs(as.numeric(difftime(timestamp, before, units = "secs"))), 60)
  expect_error(doc_record_timestamps(doc, NA), "record")
})

test_that("checkout shows an earlier version read-only", {
  h = history_doc()
  expect_false(doc_is_detached(h$doc))

  doc_checkout(h$doc, h$v1)
  expect_true(doc_is_detached(h$doc))
  expect_identical(text_get(h$text), "Hello")
  expect_identical(doc_frontiers(h$doc), h$v1)
  expect_error(text_insert(h$text, 1, "x"), "detached")
  expect_identical(nrow(doc_changes(h$doc)), 2L)

  doc_checkout(h$doc)
  expect_false(doc_is_detached(h$doc))
  expect_identical(text_get(h$text), "Hello world")
  text_insert(h$text, 1, "x")
  expect_identical(text_get(h$text), "xHello world")
})

test_that("updates imported while detached appear after returning", {
  h = history_doc()
  other = doc_fork(h$doc)
  text_insert(doc_text(other), 12, "!")

  doc_checkout(h$doc, h$v1)
  doc_import(h$doc, doc_export(other, "updates"))
  expect_identical(text_get(h$text), "Hello")

  doc_checkout(h$doc)
  expect_identical(text_get(h$text), "Hello world!")
})

test_that("a fork can be taken at an earlier version", {
  h = history_doc()
  fork = doc_fork(h$doc, at = h$v1)
  expect_identical(text_get(doc_text(fork)), "Hello")
  expect_false(doc_is_detached(fork))

  text_insert(doc_text(fork), 6, "!")
  expect_identical(text_get(h$text), "Hello world")
  expect_error(doc_fork(h$doc, at = "v1"), "at")
})

test_that("revert restores contents and keeps history", {
  h = history_doc()
  map_set(doc_map(h$doc, "m"), "k", 1L)
  doc_commit(h$doc, "map")
  expect_identical(nrow(doc_changes(h$doc)), 3L)

  doc_revert_to(h$doc, h$v1)
  expect_identical(text_get(h$text), "Hello")
  expect_identical(map_keys(doc_map(h$doc, "m")), character())
  expect_false(doc_is_detached(h$doc))
  expect_gte(nrow(doc_changes(h$doc)), 3L)

  other = loro_doc()
  doc_import(other, doc_export(h$doc))
  expect_identical(text_get(doc_text(other)), "Hello")
})

test_that("diffs describe text changes in both directions", {
  h = history_doc()
  forward = doc_diff(h$doc, h$v1, h$v2)
  expect_identical(
    forward,
    list(`cid:root-text:Text` = list(
      type = "text",
      delta = list(list(retain = 5L), list(insert = " world"))
    ))
  )

  backward = doc_diff(h$doc, h$v2, h$v1)
  expect_identical(
    backward[[1]]$delta,
    list(list(retain = 5L), list(delete = 6L))
  )
  expect_identical(doc_diff(h$doc, h$v1, h$v1), structure(list(), names = character()))
})

test_that("a text diff can be applied as a delta", {
  h = history_doc()
  fork = doc_fork(h$doc, at = h$v1)
  text_apply_delta(doc_text(fork), doc_diff(h$doc, h$v1, h$v2)[[1]]$delta)
  expect_identical(text_get(doc_text(fork)), "Hello world")
})

test_that("diffs describe map, list, and mark changes", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  map = doc_map(doc, "m")
  items = doc_list(doc, "l")
  text_insert(text, 1, "abcd")
  map_set(map, "gone", 1L)
  list_push(items, "x")
  v1 = doc_frontiers(doc)

  map_set(map, "k", "v")
  map_delete(map, "gone")
  list_push(items, list(1L, 2L))
  list_delete(items, 1)
  text_mark(text, 1, 2, "bold")
  diff = doc_diff(doc, v1, doc_frontiers(doc))

  expect_setequal(names(diff), c("cid:root-text:Text", "cid:root-m:Map", "cid:root-l:List"))
  expect_identical(
    diff[["cid:root-m:Map"]],
    list(type = "map", updated = list(gone = NULL, k = "v"))
  )
  expect_identical(
    diff[["cid:root-l:List"]],
    list(type = "list", delta = list(list(insert = list(list(1L, 2L))), list(delete = 1L)))
  )
  expect_identical(
    diff[["cid:root-text:Text"]]$delta,
    list(list(retain = 2L, attributes = list(bold = TRUE)))
  )
})

test_that("invalid versions are errors", {
  h = history_doc()
  expect_error(doc_checkout(h$doc, "v1"), "frontiers")
  expect_error(doc_checkout(h$doc, raw()), "valid")
  expect_error(doc_revert_to(h$doc, 1), "frontiers")
  expect_error(doc_diff(h$doc, h$v1, "x"), "to")

  other = loro_doc(peer_id = 9)
  text_insert(doc_text(other), 1, "zzz")
  expect_error(doc_checkout(h$doc, doc_frontiers(other)), "not contained")
  expect_false(doc_is_detached(h$doc))
})

test_that("commit messages are validated", {
  doc = loro_doc()
  expect_error(doc_commit(doc, 1), "message")
})
