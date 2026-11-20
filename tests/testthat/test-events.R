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
  child = map_set_container(map, "body", "text")
  doc_commit(doc)

  seen = collector()
  sub = doc_subscribe(doc, seen$add, container = map)
  on.exit(unsubscribe(sub))

  text_insert(doc_text(doc), 1, "elsewhere")
  doc_commit(doc)
  expect_length(seen$get(), 0)

  map_set(map, "k", 1L)
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

  map_set(doc_map(a), "k", TRUE)
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
      map_set(map, "seen", TRUE)
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
