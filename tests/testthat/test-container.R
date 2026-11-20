test_that("root handles have the expected classes and ids", {
  doc = loro_doc()
  text = doc_text(doc, "t")
  map = doc_map(doc, "m")
  list = doc_list(doc, "l")

  expect_s3_class(text, "creditor::loro_text")
  expect_s3_class(map, "creditor::loro_map")
  expect_s3_class(list, "creditor::loro_list")

  expect_identical(container_id(text), "cid:root-t:Text")
  expect_identical(container_id(map), "cid:root-m:Map")
  expect_identical(container_id(list), "cid:root-l:List")
})

test_that("handles to the same container share state", {
  doc = loro_doc()
  text_insert(doc_text(doc), 1, "x")
  expect_identical(text_get(doc_text(doc)), "x")
})

test_that("a handle keeps its document alive", {
  text = local({
    doc = loro_doc()
    doc_text(doc)
  })
  invisible(gc())
  text_insert(text, 1, "still here")
  expect_identical(text_get(text), "still here")
})

test_that("container_value expands nested containers", {
  doc = loro_doc()
  root = doc_map(doc, "root")
  items = map_set_container(root, "items", "list")
  body = list_push_container(items, "text")
  text_insert(body, 1, "nested")
  list_push(items, 2L)

  expect_identical(container_value(body), "nested")
  expect_identical(container_value(items), list("nested", 2L))
  expect_identical(container_value(root), list(items = list("nested", 2L)))
  expect_identical(doc_value(doc), list(root = list(items = list("nested", 2L))))
})

test_that("nested containers sync and merge", {
  a = loro_doc(peer_id = 1)
  body = map_set_container(doc_map(a, "root"), "body", "text")
  text_insert(body, 1, "Hello")

  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))
  body_b = map_get(doc_map(b, "root"), "body")
  expect_s3_class(body_b, "creditor::loro_text")
  expect_identical(container_id(body_b), container_id(body))

  text_insert(body, 6, " world")
  text_insert(body_b, 1, ">> ")
  map_set(doc_map(b, "root"), "seen", TRUE)

  doc_import(b, doc_export(a, "updates", from = doc_version(b)))
  doc_import(a, doc_export(b, "updates", from = doc_version(a)))

  expect_identical(text_get(body), ">> Hello world")
  expect_identical(doc_value(a), doc_value(b))
  expect_identical(map_get(doc_map(a, "root"), "seen"), TRUE)
})

test_that("handles are type checked", {
  doc = loro_doc()
  expect_error(container_value(doc), "loro_container")
  expect_error(container_id("x"), "loro_container")
  expect_error(map_set(doc_text(doc), "k", 1), "loro_map")
  expect_error(list_push(doc_map(doc), 1), "loro_list")
  expect_error(doc_map(doc, 1), "name")
})

test_that("containers print their id and contents", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "hi")
  header = NULL
  contents = utils::capture.output({
    header = cli::cli_fmt(print(text))
  })
  expect_match(header[1], "loro_text")
  expect_match(header[1], "cid:root-text:Text", fixed = TRUE)
  expect_match(contents, "hi")
})
