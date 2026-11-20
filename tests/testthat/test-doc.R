test_that("peer ids round trip", {
  expect_identical(doc_peer_id(loro_doc(peer_id = 42)), "42")
  expect_identical(
    doc_peer_id(loro_doc(peer_id = "18446744073709551000")),
    "18446744073709551000"
  )
  expect_match(doc_peer_id(loro_doc()), "^[0-9]+$")
  expect_error(loro_doc(peer_id = -1), "peer_id")
  expect_error(loro_doc(peer_id = "abc"), "peer_id")
})

test_that("a snapshot reproduces the document", {
  a = loro_doc()
  text_insert(doc_text(a), 1, "Hello")

  b = loro_doc()
  doc_import(b, doc_export(a))
  expect_identical(text_get(doc_text(b)), "Hello")
  expect_identical(doc_version(b), doc_version(a))
})

test_that("concurrent edits converge", {
  a = loro_doc(peer_id = 1)
  text_insert(doc_text(a), 1, "Hello")

  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))

  text_insert(doc_text(a), 6, " world")
  text_insert(doc_text(b), 1, ">> ")
  text_delete(doc_text(b), 4, 1)

  to_b = doc_export(a, "updates", from = doc_version(b))
  to_a = doc_export(b, "updates", from = doc_version(a))
  doc_import(b, to_b)
  doc_import(a, to_a)

  expect_identical(text_get(doc_text(a)), ">> ello world")
  expect_identical(text_get(doc_text(b)), text_get(doc_text(a)))

  doc_import(a, to_a)
  expect_identical(text_get(doc_text(a)), ">> ello world")
})

test_that("incremental updates are smaller than the full history", {
  a = loro_doc()
  text_insert(doc_text(a), 1, strrep("lorem ipsum ", 100))
  version = doc_version(a)
  text_insert(doc_text(a), 1, "x")

  expect_lt(
    length(doc_export(a, "updates", from = version)),
    length(doc_export(a, "updates"))
  )
})

test_that("a fork is independent of its source", {
  a = loro_doc()
  text_insert(doc_text(a), 1, "shared")

  b = doc_fork(a)
  expect_false(identical(doc_peer_id(a), doc_peer_id(b)))

  text_insert(doc_text(b), 7, " plus")
  expect_identical(text_get(doc_text(a)), "shared")
  expect_identical(text_get(doc_text(b)), "shared plus")
})

test_that("documents have reference semantics", {
  a = loro_doc()
  b = a
  text_insert(doc_text(b), 1, "x")
  expect_identical(text_get(doc_text(a)), "x")
})

test_that("bad sync input is an error", {
  a = loro_doc()
  expect_error(doc_import(a, "abc"), "raw")
  expect_error(doc_import(a, as.raw(1:10)))
  expect_error(doc_export(a, "updates", from = "abc"), "raw")
  expect_error(doc_export(a, "nope"))
})

test_that("print shows the peer and contents", {
  doc = loro_doc(peer_id = 7)
  text_insert(doc_text(doc), 1, "hi")
  header = NULL
  contents = utils::capture.output({
    header = cli::cli_fmt(print(doc))
  })
  expect_match(header[1], "peer 7")
  expect_match(contents, "hi")
})

test_that("the peer id can be changed", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  doc_set_peer_id(doc, 2)
  expect_identical(doc_peer_id(doc), "2")
  text_insert(doc_text(doc), 1, "b")
  doc_commit(doc)
  expect_identical(doc_changes(doc)$peer, c("1", "2"))

  doc_set_peer_id(doc, "18446744073709551000")
  expect_identical(doc_peer_id(doc), "18446744073709551000")
  expect_error(doc_set_peer_id(doc, -1), "peer_id")
  expect_error(doc_set_peer_id(doc, "x"), "peer_id")
})
