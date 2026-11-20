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

  map_set(map, k = 1L)
  list_push(items, "x")
  doc_commit(doc)
  map_set(map, k = 2L)
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
  doc_import(a, doc_export_updates(b))
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
  manager = doc_undo_manager(doc, merge_interval = 60)
  text_insert(text, 1, "a")
  doc_commit(doc)
  text_insert(text, 2, "b")
  doc_commit(doc)

  undo(manager)
  expect_identical(text_get(text), "")
})

test_that("a checkout clears the undo history", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  text_insert(text, 1, "a")
  doc_commit(doc)
  version = doc_frontiers(doc)
  text_insert(text, 2, "b")
  doc_commit(doc)
  expect_true(can_undo(manager))

  doc_checkout(doc, version)
  doc_checkout(doc)
  expect_false(can_undo(manager))
  expect_identical(text_get(text), "ab")
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

test_that("commits with an excluded origin are not undo steps", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc, exclude_origins = "sys")

  text_insert(text, 1, "u")
  doc_commit(doc, origin = "user")
  text_insert(text, 1, "s")
  doc_commit(doc, origin = "sys:autosave")
  text_insert(text, 1, "n")
  doc_commit(doc)
  expect_identical(undo_count(manager), 2L)

  undo(manager)
  undo(manager)
  expect_identical(text_get(text), "s")
  expect_identical(redo_count(manager), 2L)
  expect_error(doc_undo_manager(doc, exclude_origins = NA_character_), "exclude_origins")
  expect_error(doc_undo_manager(doc, exclude_origins = 1), "exclude_origins")
})

test_that("undo and redo are labeled with the origin undo", {
  doc = loro_doc()
  manager = doc_undo_manager(doc)
  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)

  origins = character()
  sub = doc_subscribe(doc, function(event) origins <<- c(origins, event$origin))
  on.exit(unsubscribe(sub))
  undo(manager)
  redo(manager)
  expect_identical(origins, c("undo", "undo"))
})

test_that("steps can be counted, paused, and cleared", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  expect_identical(c(undo_count(manager), redo_count(manager)), c(0L, 0L))
  expect_false(undo_is_paused(manager))

  text_insert(text, 1, "a")
  doc_commit(doc)
  undo_pause(manager)
  expect_true(undo_is_paused(manager))
  text_insert(text, 2, "b")
  doc_commit(doc)
  expect_identical(undo_count(manager), 1L)

  undo_resume(manager)
  expect_false(undo_is_paused(manager))
  text_insert(text, 3, "c")
  doc_commit(doc)
  expect_identical(undo_count(manager), 2L)

  undo(manager)
  expect_identical(text_get(text), "ab")
  expect_identical(redo_count(manager), 1L)

  undo_clear(manager)
  expect_identical(c(undo_count(manager), redo_count(manager)), c(0L, 0L))
  expect_false(undo(manager))
  expect_identical(text_get(text), "ab")
  expect_error(undo_clear("x"), "loro_undo_manager")
})

test_that("a group holds exactly the edits made inside it", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)

  text_insert(text, 1, "before ")
  undo_group(manager, text_insert(text, 1, "X"))
  text_insert(text, 1, "Z")
  doc_commit(doc)
  expect_identical(text_get(text), "ZXbefore ")
  expect_identical(undo_count(manager), 3L)

  undo(manager)
  expect_identical(text_get(text), "Xbefore ")
  undo(manager)
  expect_identical(text_get(text), "before ")
})

test_that("a group delivers its events when it ends", {
  doc = loro_doc()
  manager = doc_undo_manager(doc)
  seen = 0
  sub = doc_subscribe(doc, function(event) seen <<- seen + 1)
  on.exit(unsubscribe(sub))
  undo_group(manager, text_insert(doc_text(doc), 1, "a"))
  expect_identical(seen, 1)
})

test_that("groups cannot be nested", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  expect_error(
    undo_group(manager, undo_group(manager, text_insert(text, 1, "a"))),
    "cannot be nested"
  )
  text_insert(text, 1, "b")
  doc_commit(doc)
  expect_true(undo(manager))
})

test_that("undoing a container deletion restores it under a new id", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  child = map_set_container(map, "c", "map")
  map_set(child, k = 1L)
  doc_commit(doc)
  manager = doc_undo_manager(doc)

  map_delete(map, "c")
  doc_commit(doc)
  undo(manager)

  revived = map_get(map, "c")
  expect_identical(container_value(revived), list(k = 1L))
  expect_false(identical(container_id(revived), container_id(child)))
  expect_true(container_is_deleted(child))
  expect_error(map_set(child, k = 2L), "deleted")
})

test_that("undo and redo restore nested structures", {
  doc = loro_doc(peer_id = 1)
  manager = doc_undo_manager(doc)
  map = doc_map(doc, "m")
  text_insert(map_set_container(map, "body", "text"), 1, "hello")
  doc_commit(doc)
  items = map_set_container(map, "items", "movable_list")
  list_push(items, 1L)
  map_set(list_push_container(items, "map"), x = 1)
  doc_commit(doc)
  value = doc_value(doc)

  undo(manager)
  expect_identical(doc_value(doc), list(m = list(body = "hello")))
  redo(manager)
  expect_identical(doc_value(doc), value)
})

test_that("undo of a counter keeps remote increments", {
  a = loro_doc(peer_id = 1)
  manager = doc_undo_manager(a)
  counter_increment(doc_counter(a), 1)
  doc_commit(a)
  b = doc_fork(a)
  counter_increment(doc_counter(b), 1)
  doc_import(a, doc_export_updates(b))
  expect_identical(counter_get(doc_counter(a)), 2)

  undo(manager)
  expect_identical(counter_get(doc_counter(a)), 1)
  redo(manager)
  expect_identical(counter_get(doc_counter(a)), 2)
})

test_that("the oldest steps are dropped beyond max_steps", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc, max_steps = 3)
  for (letter in c("a", "b", "c", "d", "e")) {
    text_insert(text, text_length(text) + 1, letter)
    doc_commit(doc)
  }
  expect_identical(undo_count(manager), 3L)
  while (undo(manager)) NULL
  expect_identical(text_get(text), "ab")
})

test_that("undo can be called from a callback", {
  doc = loro_doc()
  text = doc_text(doc)
  manager = doc_undo_manager(doc)
  origins = character()
  sub = doc_subscribe(doc, function(event) {
    origins <<- c(origins, event$origin)
    if (event$origin == "bad") undo(manager)
  })
  on.exit(unsubscribe(sub))

  text_insert(text, 1, "keep")
  doc_commit(doc)
  text_insert(text, 5, " oops")
  doc_commit(doc, origin = "bad")
  expect_identical(text_get(text), "keep")
  expect_identical(origins, c("", "bad", "undo"))
})
