two_versions = function() {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  text_insert(text, 1, "Hello")
  doc_commit(doc)
  v1 = doc_frontiers(doc)

  text_insert(text, 6, " world")
  map = doc_map(doc, "m")
  map_set(map, "k", 1L)
  text_insert(map_set_container(map, "body", "text"), 1, "child")
  doc_commit(doc)
  list(doc = doc, v1 = v1, v2 = doc_frontiers(doc))
}

test_that("a span of history can be undone and replayed", {
  h = two_versions()
  after = doc_value(h$doc)

  doc_apply_diff(h$doc, h$v2, h$v1)
  expect_identical(doc_value(h$doc), list(m = structure(list(), names = character()), text = "Hello"))

  doc_apply_diff(h$doc, h$v1, h$v2)
  expect_identical(doc_value(h$doc), after)
  expect_false(doc_is_detached(h$doc))
})

test_that("applied changes sync like ordinary edits", {
  h = two_versions()
  other = loro_doc(peer_id = 2)
  doc_import(other, doc_export(h$doc))

  doc_apply_diff(h$doc, h$v2, h$v1)
  doc_import(other, doc_export(h$doc, "updates", from = doc_version(other)))
  expect_identical(text_get(doc_text(other)), "Hello")
})

test_that("changes can be copied into another document", {
  h = two_versions()
  other = loro_doc(peer_id = 2)
  text_insert(doc_text(other), 1, "Hello")

  doc_apply_diff(other, h$v1, h$v2, source = h$doc)
  expect_identical(doc_value(other), doc_value(h$doc))

  body = map_get(doc_map(other, "m"), "body")
  expect_s3_class(body, "creditor::loro_text")
  text_insert(body, 6, "!")
  expect_identical(text_get(body), "child!")
  expect_identical(doc_peer_id(other), "2")
  expect_identical(unique(doc_changes(other)$peer), "2")
})

test_that("a diff that does not fit the target is an error", {
  h = two_versions()
  empty = loro_doc(peer_id = 3)
  expect_error(doc_apply_diff(empty, h$v1, h$v2, source = h$doc), "out of bound")
})

test_that("apply diff arguments are validated", {
  h = two_versions()
  expect_error(doc_apply_diff(h$doc, "v1", h$v2), "from")
  expect_error(doc_apply_diff(h$doc, h$v1, 2), "to")
  expect_error(doc_apply_diff(h$doc, h$v1, h$v2, source = "doc"), "source")
  expect_error(doc_apply_diff("doc", h$v1, h$v2), "loro_doc")

  other = loro_doc(peer_id = 9)
  text_insert(doc_text(other), 1, "zzz")
  expect_error(doc_apply_diff(h$doc, h$v1, doc_frontiers(other)), "not contained")
})
