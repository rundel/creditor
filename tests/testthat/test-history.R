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
  doc_import(a, doc_export_updates(b))

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
  doc_import(h$doc, doc_export_updates(other))
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
  map_set(doc_map(h$doc, "m"), k = 1L)
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
  map_set(map, gone = 1L)
  list_push(items, "x")
  v1 = doc_frontiers(doc)

  map_set(map, k = "v")
  map_delete(map, "gone")
  list_push(items, list(1L, 2L))
  list_delete(items, 1)
  text_mark(text, 1, 2, bold = TRUE)
  diff = doc_diff(doc, v1, doc_frontiers(doc))

  expect_setequal(names(diff), c("cid:root-text:Text", "cid:root-m:Map", "cid:root-l:List"))
  expect_identical(
    diff[["cid:root-m:Map"]],
    list(type = "map", updated = list(k = "v"), deleted = "gone")
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
  expect_error(doc_checkout(h$doc, raw()), "as_frontiers")
  expect_error(doc_checkout(h$doc, as_frontiers(raw())), "valid")
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

test_that("frontiers and version vectors convert both ways", {
  doc = loro_doc(peer_id = 1)
  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc, "one")
  frontiers = doc_frontiers(doc)
  version = doc_version(doc)
  text_insert(doc_text(doc), 2, "b")
  doc_commit(doc, "two")

  expect_identical(doc_frontiers_to_version(doc, frontiers), version)
  expect_identical(doc_version_to_frontiers(doc, version), frontiers)

  since_first = doc_frontiers_to_version(doc, doc_changes(doc)$frontiers[[1]])
  updates = doc_export_updates(doc, from = since_first)
  expect_identical(blob_metadata(updates)$changes, 1L)

  other = loro_doc(peer_id = 9)
  text_insert(doc_text(other), 1, "z")
  expect_error(doc_frontiers_to_version(doc, doc_frontiers(other)), "not part")
  expect_error(doc_frontiers_to_version(doc, "x"), "frontiers")
  expect_error(doc_version_to_frontiers(doc, "x"), "version")
})

test_that("versions can be ordered", {
  h = history_doc()
  expect_identical(doc_compare_frontiers(h$doc, h$v1, h$v2), -1L)
  expect_identical(doc_compare_frontiers(h$doc, h$v2, h$v1), 1L)
  expect_identical(doc_compare_frontiers(h$doc, h$v1, h$v1), 0L)

  branch = doc_fork(h$doc, at = h$v1)
  text_insert(doc_text(branch), 1, "B")
  side = doc_frontiers(branch)
  doc_import(h$doc, doc_export_updates(branch))
  expect_identical(doc_compare_frontiers(h$doc, h$v2, side), NA_integer_)
  expect_identical(doc_compare_frontiers(h$doc, h$v1, side), -1L)

  stranger = loro_doc(peer_id = 9)
  text_insert(doc_text(stranger), 1, "z")
  expect_error(doc_compare_frontiers(h$doc, h$v1, doc_frontiers(stranger)), "not included")
})

test_that("history can be counted and looked up", {
  h = history_doc()
  expect_identical(doc_change_count(h$doc), 2L)
  expect_identical(doc_op_count(h$doc), 11L)
  expect_identical(doc_change_count(loro_doc()), 0L)

  changes = doc_changes(h$doc)
  expect_identical(doc_change(h$doc, "1", 0), changes[1, ])
  expect_identical(doc_change(h$doc, "1", 3)$message, "greeting")
  second = doc_change(h$doc, "1", 7)
  expect_identical(second$message, "audience")
  expect_identical(second$frontiers, list(h$v2))

  expect_error(doc_change(h$doc, "1", 999), "no change")
  expect_error(doc_change(h$doc, "77", 0), "no change")
  expect_error(doc_change(h$doc, 1, 0), "peer")
  expect_error(doc_change(h$doc, "1", -1), "counter")
})

test_that("the containers touched by changes are reported", {
  h = history_doc()
  map_set(doc_map(h$doc, "m"), k = 1L)
  doc_commit(h$doc, "map")
  changes = doc_changes(h$doc)

  expect_identical(doc_changed_containers(h$doc, changes[1, ]), "cid:root-text:Text")
  expect_identical(doc_changed_containers(h$doc, changes[3, ]), "cid:root-m:Map")
  expect_identical(
    doc_changed_containers(h$doc, changes),
    c("cid:root-m:Map", "cid:root-text:Text")
  )
  expect_identical(doc_changed_containers(h$doc, changes[0, ]), character())
  expect_error(doc_changed_containers(h$doc, "x"), "data frame")
  expect_error(doc_changed_containers(h$doc, data.frame(peer = "1")), "columns")
})

test_that("detached editing is off by default", {
  h = history_doc()
  expect_false(doc_is_detached_editing(h$doc))
  doc_checkout(h$doc, h$v1)
  expect_error(text_insert(h$text, 1, "x"), "detached")
  expect_error(doc_set_detached_editing(h$doc, NA), "enable")
})

test_that("edits made while detached form a branch that merges", {
  h = history_doc()
  doc_set_detached_editing(h$doc)
  expect_true(doc_is_detached_editing(h$doc))

  doc_checkout(h$doc, h$v1)
  expect_false(identical(doc_peer_id(h$doc), "1"))
  text_insert(h$text, 6, "!")
  doc_commit(h$doc, "branch")
  expect_identical(text_get(h$text), "Hello!")
  expect_true(doc_is_detached(h$doc))

  branch = doc_frontiers(h$doc)
  expect_identical(doc_compare_frontiers(h$doc, h$v2, branch), NA_integer_)
  expect_identical(doc_compare_frontiers(h$doc, h$v1, branch), -1L)

  doc_checkout(h$doc)
  expect_false(doc_is_detached(h$doc))
  expect_identical(text_get(h$text), "Hello world!")
  expect_identical(doc_changes(h$doc)$message, c("greeting", "audience", "branch"))

  other = loro_doc()
  doc_import(other, doc_export(h$doc))
  expect_identical(text_get(doc_text(other)), "Hello world!")

  doc_set_detached_editing(h$doc, FALSE)
  doc_checkout(h$doc, h$v1)
  expect_error(text_insert(h$text, 1, "x"), "detached")
})

test_that("a document can be detached at its current version", {
  doc = loro_doc(peer_id = 3)
  text = doc_text(doc)
  text_insert(text, 1, "a")
  other = doc_fork(doc)
  text_insert(doc_text(other), 2, "b")

  doc_detach(doc)
  expect_true(doc_is_detached(doc))
  expect_error(text_insert(text, 1, "x"), "detached")
  doc_import(doc, doc_export_updates(other))
  expect_identical(text_get(text), "a")

  doc_checkout(doc)
  expect_identical(text_get(text), "ab")
})

test_that("a commit can carry an explicit timestamp", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  when = as.POSIXct("2020-01-02 03:04:05", tz = "UTC")

  text_insert(text, 1, "a")
  doc_commit(doc, "first", timestamp = when)
  text_insert(text, 1, "b")
  doc_commit(doc, "second", timestamp = 1600000000)
  text_insert(text, 1, "c")
  doc_commit(doc, "earlier", timestamp = 1000)

  changes = doc_changes(doc)
  expect_identical(changes$timestamp[1], when)
  expect_identical(as.numeric(changes$timestamp[2]), 1600000000)
  expect_identical(as.numeric(changes$timestamp[3]), 1600000000)

  expect_error(doc_commit(doc, timestamp = "2020"), "timestamp")
  expect_error(doc_commit(doc, timestamp = -5), "timestamp")
  expect_error(doc_commit(doc, timestamp = c(1, 2)), "timestamp")
})

test_that("versions and frontiers cannot be swapped", {
  h = history_doc()
  version = doc_version(h$doc)
  frontiers = doc_frontiers(h$doc)
  expect_s3_class(version, "loro_version")
  expect_s3_class(frontiers, "loro_frontiers")
  expect_s3_class(doc_changes(h$doc)$frontiers[[1]], "loro_frontiers")

  expect_error(doc_checkout(h$doc, version), "not a version vector")
  expect_error(doc_fork(h$doc, at = version), "not a version vector")
  expect_error(doc_diff(h$doc, version, frontiers), "not a version vector")
  expect_error(doc_revert_to(h$doc, version), "not a version vector")
  expect_error(doc_export_shallow(h$doc, since = version), "not a version vector")
  expect_error(doc_frontiers_to_version(h$doc, version), "not a version vector")
  expect_error(doc_export_updates(h$doc, from = frontiers), "not frontiers")
  expect_error(doc_export_json(h$doc, from = frontiers), "not frontiers")
  expect_error(doc_version_to_frontiers(h$doc, frontiers), "not frontiers")
  expect_error(doc_export_updates(h$doc, from = unclass(version)), "as_version")
  expect_false(doc_is_detached(h$doc))
})

test_that("saved versions can be restored", {
  h = history_doc()
  frontiers = doc_frontiers(h$doc)
  version = doc_version(h$doc)
  expect_identical(as_frontiers(unclass(frontiers)), frontiers)
  expect_identical(as_version(unclass(version)), version)
  expect_error(as_frontiers("x"), "raw")
  expect_error(as_version(1), "raw")

  expect_match(format(frontiers), "^<loro_frontiers> [0-9a-f ]+$")
  expect_match(format(version), "^<loro_version> [0-9a-f ]+$")
  expect_output(print(frontiers), "loro_frontiers")
  expect_output(print(version), "loro_version")
})

test_that("frontiers with two heads work everywhere", {
  a = loro_doc(peer_id = 1)
  text = doc_text(a)
  text_insert(text, 1, "base")
  doc_commit(a)
  b = doc_fork(a)
  doc_set_peer_id(b, 2)
  text_insert(text, 1, "A")
  doc_commit(a)
  text_insert(doc_text(b), 5, "B")
  doc_commit(b)
  from_a = doc_frontiers(a)
  from_b = doc_frontiers(b)
  doc_import(a, doc_export_updates(b))
  merged = doc_frontiers(a)

  expect_gt(length(merged), length(from_a))
  expect_identical(doc_compare_frontiers(a, from_a, merged), -1L)
  expect_identical(doc_compare_frontiers(a, merged, from_b), 1L)
  expect_identical(doc_compare_frontiers(a, merged, merged), 0L)
  expect_identical(doc_frontiers_to_version(a, merged), doc_version(a))
  expect_identical(doc_version_to_frontiers(a, doc_version(a)), merged)

  text_insert(text, 1, "later ")
  doc_checkout(a, merged)
  expect_identical(text_get(text), "AbaseB")
  expect_identical(doc_frontiers(a), merged)
  doc_checkout(a)
  expect_identical(text_get(doc_text(doc_fork(a, at = merged))), "AbaseB")
  doc_revert_to(a, merged)
  expect_identical(text_get(text), "AbaseB")
})

test_that("an empty document has a usable empty version", {
  empty = loro_doc()
  start = doc_frontiers(empty)
  expect_identical(doc_diff(empty, start, start), structure(list(), names = character()))
  expect_identical(doc_compare_frontiers(empty, start, start), 0L)
  expect_identical(doc_version_to_frontiers(empty, doc_version(empty)), start)

  for (export in list(doc_export, doc_export_updates, doc_export_shallow)) {
    other = loro_doc()
    doc_import(other, export(empty))
    status = doc_import_status(other)
    expect_identical(nrow(status$success), 0L)
    expect_identical(nrow(doc_changes(other)), 0L)
  }
  other = loro_doc()
  doc_import_json(other, doc_export_json(empty))
  expect_identical(blob_metadata(doc_export(empty))$changes, 0L)

  h = history_doc()
  diff = doc_diff(h$doc, start, doc_frontiers(h$doc))
  expect_identical(diff[[1]]$delta, list(list(insert = "Hello world")))
  doc_revert_to(h$doc, start)
  expect_identical(text_get(h$text), "")
})

test_that("a map diff separates deleted keys from keys set to NULL", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  map_set(map, nulled = 1L)
  map_set(map, gone = 1L)
  before = doc_frontiers(doc)
  map_set(map, nulled = NULL)
  map_delete(map, "gone")

  diff = doc_diff(doc, before, doc_frontiers(doc))[["cid:root-m:Map"]]
  expect_identical(diff, list(type = "map", updated = list(nulled = NULL), deleted = "gone"))
  expect_identical(map_keys(map), "nulled")

  back = doc_diff(doc, doc_frontiers(doc), before)[["cid:root-m:Map"]]
  expect_identical(back$updated, list(gone = 1L, nulled = 1L))
  expect_identical(back$deleted, character())
})

test_that("revert and apply diff commit their changes", {
  a = loro_doc(peer_id = 1)
  text = doc_text(a)
  text_insert(text, 1, "abc")
  doc_commit(a)
  v1 = doc_frontiers(a)
  text_insert(text, 4, "def")
  doc_commit(a)
  v2 = doc_frontiers(a)

  b = doc_fork(a)
  events = 0
  live = doc_subscribe_local_updates(a, function(bytes) doc_import(b, bytes))
  watch = doc_subscribe(a, function(event) events <<- events + 1)
  manager = doc_undo_manager(a)
  on.exit({
    unsubscribe(live)
    unsubscribe(watch)
  })

  doc_revert_to(a, v1)
  expect_identical(text_get(doc_text(b)), "abc")
  expect_identical(events, 1)
  expect_identical(undo_count(manager), 1L)

  doc_apply_diff(a, v1, v2)
  expect_identical(text_get(doc_text(b)), "abcdef")
  expect_identical(events, 2)
  expect_identical(undo_count(manager), 2L)
})

test_that("a failed apply diff leaves the target unchanged", {
  source = loro_doc(peer_id = 1)
  before = doc_frontiers(source)
  map_set(doc_map(source, "a"), k = 1L)
  text_insert(doc_text(source, "t"), 1, "hello")
  doc_commit(source)
  from = doc_frontiers(source)
  text_delete(doc_text(source, "t"), 2, 4)
  map_set(doc_map(source, "z"), k = 2L)
  doc_commit(source)

  target = loro_doc(peer_id = 2)
  text_insert(doc_text(target, "t"), 1, "x")
  doc_commit(target)
  value = doc_value(target)
  version = doc_version(target)

  expect_error(doc_apply_diff(target, from, doc_frontiers(source), source = source))
  expect_identical(doc_value(target), value)
  expect_identical(doc_version(target), version)
})

test_that("commit messages keep their text", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  message = "héllo 日本 \U0001F600"
  text_insert(text, 1, "a")
  doc_commit(doc, message)
  expect_identical(doc_changes(doc)$message, message)

  other = loro_doc()
  doc_import_json(other, doc_export_json(doc))
  expect_identical(doc_changes(other)$message, message)

  text_insert(text, 1, "b")
  doc_commit(doc, "")
  expect_identical(doc_changes(doc)$message[2], NA_character_)

  doc_commit(doc, "dropped")
  text_insert(text, 1, "c")
  doc_commit(doc)
  expect_false("dropped" %in% doc_changes(doc)$message)
})

test_that("changed containers rejects missing ids", {
  h = history_doc()
  changes = doc_changes(h$doc)
  changes$counter[1] = NA
  expect_error(doc_changed_containers(h$doc, changes), "missing")
})

test_that("a container's deleted status follows checkout", {
  doc = loro_doc()
  items = doc_movable_list(doc, "l")
  child = loro_text()
  list_push(items, child)
  doc_commit(doc)
  version = doc_frontiers(doc)
  list_set(items, 1, 1L)
  expect_true(container_is_deleted(child))

  doc_checkout(doc, version)
  expect_false(container_is_deleted(child))
  doc_checkout(doc)
  expect_true(container_is_deleted(child))
})

test_that("a fork of a detached document starts from the checked out version", {
  h = history_doc()
  doc_checkout(h$doc, h$v1)
  fork = doc_fork(h$doc)
  expect_false(doc_is_detached(fork))
  expect_identical(text_get(doc_text(fork)), "Hello")

  copy = loro_doc()
  doc_import(copy, doc_export(h$doc))
  expect_identical(text_get(doc_text(copy)), "Hello world")
  expect_true(doc_is_detached(h$doc))
})
