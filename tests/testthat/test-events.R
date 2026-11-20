collector = function() {
  events = list()
  list(
    add = function(event) events[[length(events) + 1]] <<- event,
    get = function() events
  )
}

test_that("local commits are reported with their diff", {
  doc = loro_doc(peer_id = 1)
  seen = collector()
  sub = doc_subscribe(doc, seen$add)
  on.exit(unsubscribe(sub))

  text_insert(doc_text(doc), 1, "Hello")
  expect_length(seen$get(), 0)

  doc_commit(doc)
  expect_identical(
    seen$get(),
    list(list(
      by = "local",
      origin = "",
      diff = list(`cid:root-text:Text` = list(
        type = "text",
        delta = list(list(insert = "Hello"))
      ))
    ))
  )

  doc_commit(doc)
  expect_length(seen$get(), 1)
})

test_that("imports and checkouts are reported", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  seen = collector()
  sub = doc_subscribe(b, seen$add)
  on.exit(unsubscribe(sub))

  text_insert(doc_text(a), 1, "Hello")
  doc_commit(a, "one")
  text_insert(doc_text(a), 6, "!")
  doc_import(b, doc_export(a))
  expect_identical(vapply(seen$get(), `[[`, "", "by"), "import")

  doc_checkout(b, doc_changes(b)$frontiers[[1]])
  doc_checkout(b)
  expect_identical(
    vapply(seen$get(), `[[`, "", "by"),
    c("import", "checkout", "checkout")
  )
})

test_that("an implicit commit also delivers events", {
  doc = loro_doc()
  seen = collector()
  sub = doc_subscribe(doc, seen$add)
  on.exit(unsubscribe(sub))

  text_insert(doc_text(doc), 1, "a")
  doc_export(doc)
  expect_length(seen$get(), 1)
})

test_that("a container subscription only sees its own changes", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  child = loro_text()
  map_set(map, body = child)
  doc_commit(doc)

  seen = collector()
  sub = doc_subscribe(doc, seen$add, container = map)
  on.exit(unsubscribe(sub))

  text_insert(doc_text(doc), 1, "elsewhere")
  doc_commit(doc)
  expect_length(seen$get(), 0)

  map_set(map, k = 1L)
  doc_commit(doc)
  text_insert(child, 1, "nested")
  doc_commit(doc)
  expect_length(seen$get(), 2)
  expect_named(seen$get()[[1]]$diff, container_id(map))
  expect_named(seen$get()[[2]]$diff, container_id(child))
})

test_that("local updates can drive live sync", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  sub = doc_subscribe_local_updates(a, function(bytes) doc_import(b, bytes))
  on.exit(unsubscribe(sub))

  text_insert(doc_text(a), 1, "Hello")
  doc_commit(a)
  expect_identical(text_get(doc_text(b)), "Hello")

  map_set(doc_map(a), k = TRUE)
  doc_commit(a)
  expect_identical(doc_value(b), doc_value(a))
})

test_that("local updates are raw vectors and exclude imports", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  seen = collector()
  sub = doc_subscribe_local_updates(a, seen$add)
  on.exit(unsubscribe(sub))

  text_insert(doc_text(b), 1, "remote")
  doc_import(a, doc_export(b))
  expect_length(seen$get(), 0)

  text_insert(doc_text(a), 1, "local ")
  doc_commit(a)
  expect_length(seen$get(), 1)
  expect_type(seen$get()[[1]], "raw")
})

test_that("unsubscribe stops delivery and is idempotent", {
  doc = loro_doc()
  seen = collector()
  sub = doc_subscribe(doc, seen$add)

  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  unsubscribe(sub)
  text_insert(doc_text(doc), 1, "b")
  doc_commit(doc)

  expect_length(seen$get(), 1)
  expect_null(unsubscribe(sub))
  expect_error(unsubscribe("x"), "loro_subscription")
})

test_that("pending events are dropped by unsubscribe", {
  doc = loro_doc()
  seen = collector()
  sub = doc_subscribe(doc, seen$add)
  text_insert(doc_text(doc), 1, "a")
  unsubscribe(sub)
  doc_commit(doc)
  expect_length(seen$get(), 0)
})

test_that("a failing callback warns without interrupting the edit", {
  doc = loro_doc()
  seen = collector()
  bad = doc_subscribe(doc, function(event) stop("boom"))
  good = doc_subscribe(doc, seen$add)
  on.exit({
    unsubscribe(bad)
    unsubscribe(good)
  })

  text_insert(doc_text(doc), 1, "a")
  expect_warning(doc_commit(doc), "boom")
  expect_identical(text_get(doc_text(doc)), "a")
  expect_length(seen$get(), 1)
})

test_that("a callback can edit the document", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  calls = 0
  sub = doc_subscribe(doc, function(event) {
    calls <<- calls + 1
    if (calls == 1) {
      map_set(map, seen = TRUE)
      doc_commit(doc)
    }
  })
  on.exit(unsubscribe(sub))

  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  expect_identical(calls, 2)
  expect_identical(map_get(map, "seen"), TRUE)
})

test_that("subscription arguments are validated", {
  doc = loro_doc()
  expect_error(doc_subscribe(doc, "f"), "callback")
  expect_error(doc_subscribe("doc", identity), "loro_doc")
  expect_error(doc_subscribe(doc, identity, container = "m"), "container")
  expect_error(doc_subscribe_local_updates(doc, NULL), "callback")
})

test_that("a commit origin reaches subscribers but not history", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  seen = collector()
  remote = collector()
  sub_a = doc_subscribe(a, seen$add)
  sub_b = doc_subscribe(b, remote$add)
  on.exit({
    unsubscribe(sub_a)
    unsubscribe(sub_b)
  })

  text_insert(doc_text(a), 1, "a")
  doc_commit(a, origin = "import-script")
  text_insert(doc_text(a), 1, "b")
  doc_commit(a)
  expect_identical(vapply(seen$get(), `[[`, "", "origin"), c("import-script", ""))

  doc_import(b, doc_export(a))
  expect_identical(remote$get()[[1]]$origin, "")
  expect_error(doc_commit(a, origin = 1), "origin")
})

test_that("peer id changes are reported", {
  doc = loro_doc(peer_id = 1)
  peers = character()
  sub = doc_subscribe_peer_id(doc, function(peer) peers <<- c(peers, peer))
  on.exit(unsubscribe(sub))

  doc_set_peer_id(doc, 2)
  doc_set_peer_id(doc, 3)
  expect_identical(peers, c("2", "3"))
})

test_that("the first local commit under each peer id is reported", {
  doc = loro_doc(peer_id = 1)
  peers = character()
  sub = doc_subscribe_first_commit(doc, function(peer) peers <<- c(peers, peer))
  on.exit(unsubscribe(sub))

  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  text_insert(doc_text(doc), 1, "b")
  doc_commit(doc)
  expect_identical(peers, "1")

  doc_set_peer_id(doc, 2)
  expect_identical(peers, "1")
  text_insert(doc_text(doc), 1, "c")
  doc_commit(doc)
  expect_identical(peers, c("1", "2"))

  other = loro_doc(peer_id = 7)
  text_insert(doc_text(other), 1, "z")
  doc_import(doc, doc_export(other))
  expect_identical(peers, c("1", "2"))

  expect_error(doc_subscribe_first_commit(doc, 1), "callback")
  expect_error(doc_subscribe_peer_id("doc", identity), "loro_doc")
})

test_that("a first-commit callback can record the author", {
  doc = loro_doc(peer_id = 5)
  authors = doc_map(doc, "authors")
  sub = doc_subscribe_first_commit(doc, function(peer) {
    authors[[peer]] = "Colin"
    doc_commit(doc)
  })
  on.exit(unsubscribe(sub))

  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  expect_identical(container_value(authors), list(`5` = "Colin"))
})

test_that("every function that can commit delivers the events it causes", {
  committing = list(
    doc_commit = function(doc, v) doc_commit(doc),
    doc_export = function(doc, v) doc_export(doc),
    doc_export_updates = function(doc, v) doc_export_updates(doc),
    doc_export_json = function(doc, v) doc_export_json(doc),
    doc_import = function(doc, v) doc_import(doc, doc_export(loro_doc())),
    doc_merge = function(doc, v) doc_merge(doc, loro_doc()),
    doc_fork = function(doc, v) doc_fork(doc),
    doc_checkout = function(doc, v) doc_checkout(doc, v),
    doc_detach = function(doc, v) doc_detach(doc),
    doc_diff = function(doc, v) doc_diff(doc, v, v),
    doc_revert_to = function(doc, v) doc_revert_to(doc, v),
    doc_apply_diff = function(doc, v) doc_apply_diff(doc, v, v),
    doc_changes = function(doc, v) doc_changes(doc),
    doc_change = function(doc, v) doc_change(doc, "1", 0),
    doc_changed_containers = function(doc, v) doc_changed_containers(doc, doc_changes(doc)),
    doc_change_count = function(doc, v) doc_change_count(doc),
    doc_op_count = function(doc, v) doc_op_count(doc),
    doc_frontiers = function(doc, v) doc_frontiers(doc),
    doc_version = function(doc, v) doc_version(doc),
    doc_value = function(doc, v) doc_value(doc),
    doc_get_path = function(doc, v) doc_get(doc, "t"),
    doc_jsonpath = function(doc, v) doc_jsonpath(doc, "$.t"),
    doc_compare_frontiers = function(doc, v) doc_compare_frontiers(doc, v, v),
    doc_frontiers_to_version = function(doc, v) doc_frontiers_to_version(doc, v),
    doc_set_peer_id = function(doc, v) doc_set_peer_id(doc, 2),
    cursor_pos = function(doc, v) cursor_pos(doc, text_cursor(doc_text(doc, "t"), 1))
  )

  for (name in names(committing)) {
    doc = loro_doc(peer_id = 1)
    text = doc_text(doc, "t")
    text_insert(text, 1, "seed")
    doc_commit(doc)
    version = doc_frontiers(doc)

    seen = 0
    sub = doc_subscribe(doc, function(event) seen <<- seen + 1)
    text_insert(text, 1, "x")
    committing[[name]](doc, version)
    queued = loro_events_pending_impl() || length(the$pending) > 0L
    expect_false(queued, label = paste(name, "left an event undelivered"))

    loro_doc_commit_impl(doc@ptr, NULL, NULL, NULL)
    deliver_events()
    unsubscribe(sub)
    # A checkout or a revert adds an event of its own after the commit.
    expected = if (name %in% c("doc_checkout", "doc_revert_to")) 2 else 1
    expect_identical(seen, expected, label = paste(name, "event count"))
  }
})

test_that("events are delivered even when the committing call fails", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  seen = 0
  sub = doc_subscribe(doc, function(event) seen <<- seen + 1)
  on.exit(unsubscribe(sub))

  text_insert(text, 1, "a")
  expect_error(doc_import(doc, as.raw(1:20)))
  expect_identical(seen, 1)

  other = loro_doc(peer_id = 9)
  text_insert(doc_text(other), 1, "z")
  text_insert(text, 1, "b")
  expect_error(doc_checkout(doc, doc_frontiers(other)))
  expect_identical(seen, 2)
})

test_that("events keep their order when a callback commits", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  inserted = function(event) {
    delta = event$diff[[1]]$delta
    delta[[length(delta)]]$insert
  }
  first = character()
  second = character()
  calls = 0
  sub1 = doc_subscribe(doc, function(event) {
    first <<- c(first, inserted(event))
    calls <<- calls + 1
    if (calls == 1) {
      text_insert(text, text_length(text) + 1, "C")
      doc_commit(doc)
    }
  })
  sub2 = doc_subscribe(doc, function(event) second <<- c(second, inserted(event)))
  on.exit({
    unsubscribe(sub1)
    unsubscribe(sub2)
  })

  text_insert(text, 1, "A")
  loro_doc_commit_impl(doc@ptr, NULL, NULL, NULL)
  text_insert(text, 2, "B")
  doc_commit(doc)

  expect_identical(text_get(text), "ABC")
  expect_identical(first, c("A", "B", "C"))
  expect_identical(second, c("A", "B", "C"))
})

test_that("an interrupted delivery keeps the remaining events", {
  doc = loro_doc(peer_id = 1)
  text = doc_text(doc)
  seen = character()
  sub = doc_subscribe(doc, function(event) {
    value = event$diff[[1]]$delta
    value = value[[length(value)]]$insert
    seen <<- c(seen, value)
    if (value == "A") stop("boom")
  })
  on.exit(unsubscribe(sub))

  text_insert(text, 1, "A")
  loro_doc_commit_impl(doc@ptr, NULL, NULL, NULL)
  text_insert(text, 2, "B")
  withr_warn = options(warn = 2)
  result = tryCatch(doc_commit(doc), error = function(e) "escalated")
  options(withr_warn)
  expect_identical(result, "escalated")

  text_insert(text, 3, "C")
  doc_commit(doc)
  expect_identical(seen, c("A", "B", "C"))
})

test_that("subscriptions can change during delivery", {
  doc = loro_doc(peer_id = 1)
  log = character()
  late = NULL
  sub2 = NULL
  sub1 = doc_subscribe(doc, function(event) {
    log <<- c(log, "s1")
    unsubscribe(sub1)
    unsubscribe(sub2)
    late <<- doc_subscribe(doc, function(event) log <<- c(log, "late"))
  })
  sub2 = doc_subscribe(doc, function(event) log <<- c(log, "s2"))
  sub3 = doc_subscribe(doc, function(event) log <<- c(log, "s3"))
  on.exit({
    unsubscribe(sub3)
    if (!is.null(late)) unsubscribe(late)
  })

  text_insert(doc_text(doc), 1, "a")
  doc_commit(doc)
  expect_identical(log, c("s1", "s3"))

  text_insert(doc_text(doc), 1, "b")
  doc_commit(doc)
  expect_identical(log, c("s1", "s3", "s3", "late"))
})

test_that("two documents can sync each other without looping", {
  a = loro_doc(peer_id = 1)
  b = loro_doc(peer_id = 2)
  to_b = doc_subscribe_local_updates(a, function(bytes) doc_import(b, bytes))
  to_a = doc_subscribe_local_updates(b, function(bytes) doc_import(a, bytes))
  on.exit({
    unsubscribe(to_b)
    unsubscribe(to_a)
  })

  text_insert(doc_text(a), 1, "Hello")
  doc_commit(a)
  text_insert(doc_text(b), 1, "World")
  doc_commit(b)
  expect_identical(text_get(doc_text(a)), text_get(doc_text(b)))
  expect_identical(nchar(text_get(doc_text(a))), 10L)
})

test_that("a subscription on a dropped document does no harm", {
  seen = 0
  make = function() {
    doc = loro_doc()
    sub = doc_subscribe(doc, function(event) seen <<- seen + 1)
    text_insert(doc_text(doc), 1, "a")
    doc_commit(doc)
    sub
  }
  sub = make()
  invisible(gc())
  other = loro_doc()
  text_insert(doc_text(other), 1, "b")
  doc_commit(other)
  expect_gte(seen, 1)
  expect_null(unsubscribe(sub))
})

test_that("idle subscriptions do not slow down commits", {
  subs = lapply(1:300, function(i) doc_subscribe(loro_doc(), function(event) NULL))
  on.exit(for (sub in subs) unsubscribe(sub))
  doc = loro_doc()
  text = doc_text(doc)
  elapsed = system.time(for (i in 1:200) {
    text_insert(text, 1, "a")
    doc_commit(doc)
  })[["elapsed"]]
  expect_lt(elapsed, 2)
})

test_that("event diffs describe each container type", {
  doc = loro_doc(peer_id = 1)
  events = list()
  sub = doc_subscribe(doc, function(event) events[[length(events) + 1]] <<- event)
  on.exit(unsubscribe(sub))
  last = function() events[[length(events)]]$diff

  map = doc_map(doc, "m")
  map_set(map, a = 1L)
  map_set(map, b = 2L)
  doc_commit(doc)
  map_set(map, a = NULL)
  map_delete(map, "b")
  doc_commit(doc)
  expect_identical(
    last()[["cid:root-m:Map"]],
    list(type = "map", updated = list(a = NULL), deleted = "b")
  )

  counter_increment(doc_counter(doc, "c"), 2)
  doc_commit(doc)
  expect_identical(last()[["cid:root-c:Counter"]], list(type = "counter", increment = 2))

  items = doc_movable_list(doc, "l")
  list_push(items, "x")
  list_push(items, "y")
  doc_commit(doc)
  list_move(items, 1, 2)
  doc_commit(doc)
  expect_identical(last()[["cid:root-l:MovableList"]]$type, "list")

  tree = doc_tree(doc, "t")
  first = tree_create(tree)
  second = tree_create(tree)
  doc_commit(doc)
  tree_move(tree, first, index = 2)
  doc_commit(doc)
  expect_identical(
    last()[["cid:root-t:Tree"]]$diff,
    list(list(
      node = first, action = "move", parent = NA_character_, index = 2L,
      old_parent = NA_character_, old_index = 1L
    ))
  )
})
