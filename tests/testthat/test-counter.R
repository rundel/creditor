test_that("a counter can be incremented and read", {
  doc = loro_doc()
  counter = doc_counter(doc, "c")
  expect_s3_class(counter, "creditor::loro_counter")
  expect_identical(counter_get(counter), 0)

  counter_increment(counter)
  counter_increment(counter, 2.5)
  counter_increment(counter, -1)
  expect_identical(counter_get(counter), 2.5)
  expect_identical(container_value(counter), 2.5)
  expect_identical(doc_value(doc), list(c = 2.5))
})

test_that("concurrent increments add up", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  counter_increment(doc_counter(a), 3)
  counter_increment(doc_counter(b), 4)

  doc_import(b, doc_export(a, "updates"))
  doc_import(a, doc_export(b, "updates"))
  expect_identical(counter_get(doc_counter(a)), 7)
  expect_identical(counter_get(doc_counter(b)), 7)
})

test_that("counters nest in maps and lists", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  votes = map_set_container(map, "votes", "counter")
  counter_increment(votes, 5)
  expect_identical(counter_get(map_get(map, "votes")), 5)

  in_list = list_push_container(doc_list(doc, "l"), "counter")
  counter_increment(in_list)
  expect_identical(doc_value(doc), list(l = list(1), m = list(votes = 5)))
})

test_that("counter changes appear in diffs, history, and undo", {
  doc = loro_doc(peer_id = 1)
  counter = doc_counter(doc, "c")
  manager = doc_undo_manager(doc)
  counter_increment(counter, 2)
  doc_commit(doc)
  v1 = doc_frontiers(doc)
  counter_increment(counter, 3)
  doc_commit(doc)

  expect_identical(
    doc_diff(doc, v1, doc_frontiers(doc)),
    list(`cid:root-c:Counter` = list(type = "counter", increment = 3))
  )

  undo(manager)
  expect_identical(counter_get(counter), 2)
  redo(manager)

  doc_checkout(doc, v1)
  expect_identical(counter_get(counter), 2)
  doc_checkout(doc)
  expect_identical(counter_get(counter), 5)
})

test_that("counter arguments are validated", {
  doc = loro_doc()
  counter = doc_counter(doc)
  expect_error(counter_increment(counter, "1"), "by")
  expect_error(counter_increment(counter, NA_real_), "by")
  expect_error(counter_increment(counter, Inf), "by")
  expect_error(counter_increment(doc_text(doc), 1), "loro_counter")
  expect_error(counter_get(doc), "loro_counter")
})

test_that("a counter prints its value", {
  counter = doc_counter(loro_doc())
  counter_increment(counter, 4)
  out = utils::capture.output(invisible(cli::cli_fmt(print(counter))))
  expect_match(out, "4")
})
