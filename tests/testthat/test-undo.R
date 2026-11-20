test_that("commits are undone and redone one step at a time", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  expect_false(can_undo(manager))
  expect_false(can_redo(manager))

  text_insert(text, 1, "Hello")
  doc_commit(doc)
  text_insert(text, 6, " world")
  doc_commit(doc)
  expect_true(can_undo(manager))

  expect_true(undo(manager))
  expect_identical(text_get(text), "Hello")
  expect_true(can_redo(manager))

  expect_true(undo(manager))
  expect_identical(text_get(text), "")
  expect_false(can_undo(manager))
  expect_false(undo(manager))

  expect_true(redo(manager))
  expect_true(redo(manager))
  expect_identical(text_get(text), "Hello world")
  expect_false(redo(manager))
})

test_that("a new edit clears the redo stack", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  text_insert(text, 1, "a")
  doc_commit(doc)
  undo(manager)
  expect_true(can_redo(manager))

  text_insert(text, 1, "b")
  doc_commit(doc)
  expect_false(can_redo(manager))
})

test_that("changes made before the manager existed are not undone", {
  doc = loro_doc()
  text = doc_text(doc)
  text_insert(text, 1, "old")
  doc_commit(doc)

  manager = doc_undo_manager(doc)
  expect_false(can_undo(manager))
  expect_false(undo(manager))
  expect_identical(text_get(text), "old")
})

test_that("undo works across container types", {
  doc = loro_doc()
  manager = doc_undo_manager(doc)
  map = doc_map(doc, "m")
  items = doc_list(doc, "l")

  map_set(map, "k", 1L)
  list_push(items, "x")
  doc_commit(doc)
  map_set(map, "k", 2L)
  list_delete(items, 1)
  doc_commit(doc)

  undo(manager)
  expect_identical(map_get(map, "k"), 1L)
  expect_identical(container_value(items), list("x"))
})

test_that("a group is undone as one step", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  text_insert(text, 1, "base")
  doc_commit(doc)

  value = undo_group(manager, {
    text_insert(text, 1, "1")
    doc_commit(doc)
    text_insert(text, 1, "2")
    doc_commit(doc)
    "done"
  })
  expect_identical(value, "done")
  expect_identical(text_get(text), "21base")

  undo(manager)
  expect_identical(text_get(text), "base")
})

test_that("a group is closed when its code fails", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  expect_error(undo_group(manager, stop("inside")), "inside")

  text_insert(text, 1, "a")
  doc_commit(doc)
  text_insert(text, 1, "b")
  doc_commit(doc)
  undo(manager)
  expect_identical(text_get(text), "a")
})

test_that("undo keeps edits from other replicas", {
  a = loro_doc(peer_id = 1)
  text = doc_text(a)
  manager = doc_undo_manager(a)
  text_insert(text, 1, "Hello")
  doc_commit(a)

  b = doc_fork(a)
  text_insert(doc_text(b), 1, "REMOTE ")
  text_insert(text, 6, "!")
  doc_commit(a)
  doc_import(a, doc_export(b, "updates"))
  expect_identical(text_get(text), "REMOTE Hello!")

  undo(manager)
  expect_identical(text_get(text), "REMOTE Hello")
  undo(manager)
  expect_identical(text_get(text), "REMOTE ")
})

test_that("undo delivers events and syncs like an edit", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  manager = doc_undo_manager(a)
  sub = doc_subscribe_local_updates(a, function(bytes) doc_import(b, bytes))
  on.exit(unsubscribe(sub))

  text_insert(doc_text(a), 1, "Hello")
  doc_commit(a)
  expect_identical(text_get(doc_text(b)), "Hello")

  undo(manager)
  expect_identical(text_get(doc_text(b)), "")
})

test_that("merge_interval combines nearby commits", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc, merge_interval = 60000)
  text_insert(text, 1, "a")
  doc_commit(doc)
  text_insert(text, 2, "b")
  doc_commit(doc)

  undo(manager)
  expect_identical(text_get(text), "")
})

test_that("undo arguments are validated", {
  doc = loro_doc()
  expect_error(doc_undo_manager("doc"), "loro_doc")
  expect_error(doc_undo_manager(doc, merge_interval = -1), "merge_interval")
  expect_error(doc_undo_manager(doc, max_steps = 0), "max_steps")
  expect_error(undo(doc), "loro_undo_manager")
  expect_error(can_redo("x"), "loro_undo_manager")
})

test_that("the manager prints its step counts", {
  doc = loro_doc()
  manager = doc_undo_manager(doc)
  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  expect_match(cli::cli_fmt(print(manager)), "1 undo, 0 redo")
})
