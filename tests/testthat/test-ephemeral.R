# A store timestamps writes in whole milliseconds and ignores an incoming
# write that is not newer than what it holds, so successive writes to one key
# are spaced out wherever a test checks that the second one arrives.
tick = function() Sys.sleep(0.02)

test_that("entries can be set, read, and deleted", {
  store = ephemeral_store()
  expect_identical(ephemeral_keys(store), character())
  expect_identical(ephemeral_values(store), structure(list(), names = character()))
  expect_null(ephemeral_get(store, "missing"))

  ephemeral_set(store, b = list(name = "B", cursor = 3L))
  ephemeral_set(store, a = "x")
  expect_identical(ephemeral_keys(store), c("a", "b"))
  expect_identical(ephemeral_get(store, "a"), "x")
  expect_identical(
    ephemeral_values(store),
    list(a = "x", b = list(cursor = 3L, name = "B"))
  )

  ephemeral_delete(store, "a")
  expect_identical(ephemeral_keys(store), "b")
})

test_that("encoded state transfers between stores", {
  a = ephemeral_store()
  b = ephemeral_store()
  ephemeral_set(a, one = 1L)
  ephemeral_set(a, two = 2L)

  ephemeral_apply(b, ephemeral_encode(a, "one"))
  expect_identical(ephemeral_keys(b), "one")

  ephemeral_apply(b, ephemeral_encode(a))
  expect_identical(ephemeral_values(b), ephemeral_values(a))
})

test_that("the last write wins on every store", {
  a = ephemeral_store()
  b = ephemeral_store()
  ephemeral_set(a, k = "from a")
  tick()
  ephemeral_set(b, k = "from b")

  from_a = ephemeral_encode(a)
  from_b = ephemeral_encode(b)
  ephemeral_apply(a, from_b)
  ephemeral_apply(b, from_a)
  expect_identical(ephemeral_get(a, "k"), "from b")
  expect_identical(ephemeral_get(b, "k"), "from b")
})

test_that("local updates drive live sync, including deletes", {
  a = ephemeral_store()
  b = ephemeral_store()
  sub = ephemeral_subscribe_local_updates(a, function(bytes) ephemeral_apply(b, bytes))
  on.exit(unsubscribe(sub))

  ephemeral_set(a, k = 1L)
  expect_identical(ephemeral_get(b, "k"), 1L)
  tick()
  ephemeral_set(a, k = 2L)
  expect_identical(ephemeral_get(b, "k"), 2L)
  tick()
  ephemeral_delete(a, "k")
  expect_identical(ephemeral_keys(b), character())
})

test_that("subscribers see added, updated, and removed keys", {
  a = ephemeral_store()
  b = ephemeral_store()
  events = list()
  sub = ephemeral_subscribe(b, function(event) events[[length(events) + 1]] <<- event)
  on.exit(unsubscribe(sub))

  ephemeral_set(b, mine = TRUE)
  ephemeral_set(a, k = 1L)
  ephemeral_apply(b, ephemeral_encode(a))
  tick()
  ephemeral_set(a, k = 2L)
  ephemeral_apply(b, ephemeral_encode(a))
  tick()
  ephemeral_delete(b, "k")

  expect_identical(
    events,
    list(
      list(by = "local", added = "mine", updated = character(), removed = character()),
      list(by = "import", added = "k", updated = character(), removed = character()),
      list(by = "import", added = character(), updated = "k", removed = character()),
      list(by = "local", added = character(), updated = character(), removed = "k")
    )
  )
})

test_that("entries expire after the timeout", {
  store = ephemeral_store(timeout = 0.05)
  events = list()
  sub = ephemeral_subscribe(store, function(event) events[[length(events) + 1]] <<- event)
  on.exit(unsubscribe(sub))

  ephemeral_set(store, k = 1L)
  full = length(ephemeral_encode(store))
  Sys.sleep(0.25)
  expect_lt(length(ephemeral_encode(store)), full)
  expect_identical(ephemeral_keys(store), "k")

  ephemeral_remove_outdated(store)
  expect_identical(ephemeral_keys(store), character())
  expect_identical(events[[2]]$by, "timeout")
  expect_identical(events[[2]]$removed, "k")
})

test_that("ephemeral arguments are validated", {
  store = ephemeral_store()
  expect_error(ephemeral_store(timeout = 0), "timeout")
  expect_error(ephemeral_set("x", k = 1), "loro_ephemeral_store")
  expect_error(ephemeral_set(store, 1), "named")
  expect_error(ephemeral_set(store, k = 1, k = 2), "unique")
  expect_error(ephemeral_delete(store, 1), "keys")
  ephemeral_set(store, x = 1, y = 2, z = 3)
  ephemeral_delete(store, "x", c("y", "z"))
  expect_identical(ephemeral_keys(store), character())
  expect_error(ephemeral_set(store, k = factor("a")), "class")
  expect_error(ephemeral_apply(store, "bytes"), "raw")
  expect_error(ephemeral_apply(store, as.raw(1:9)))
  expect_error(ephemeral_subscribe(store, 1), "callback")
})

test_that("the store prints its entry count", {
  store = ephemeral_store()
  expect_match(cli::cli_fmt(print(store)), "0 entries")
})

test_that("a write in the same millisecond as the last one is not applied", {
  stale = 0L
  for (i in 1:20) {
    a = ephemeral_store()
    b = ephemeral_store()
    ephemeral_set(a, k = 1L)
    ephemeral_apply(b, ephemeral_encode(a))
    ephemeral_set(a, k = 2L)
    ephemeral_apply(b, ephemeral_encode(a))
    stale = stale + !identical(ephemeral_get(b, "k"), 2L)
  }
  skip_if(stale == 0L, "writes never landed in the same millisecond")
  expect_gt(stale, 0L)
})

test_that("damaged ephemeral bytes are clean errors", {
  store = ephemeral_store()
  ephemeral_set(store, k = list(a = 1L, b = "x"))
  bytes = ephemeral_encode(store)
  other = ephemeral_store()

  expect_error(ephemeral_apply(other, raw()))
  for (n in seq_len(length(bytes) - 1)) {
    expect_error(ephemeral_apply(other, bytes[seq_len(n)]))
  }
  expect_identical(ephemeral_keys(other), character())
  ephemeral_apply(other, bytes)
  expect_identical(ephemeral_get(other, "k"), list(a = 1L, b = "x"))
})

test_that("ephemeral values and keys convert like document values", {
  a = ephemeral_store()
  b = ephemeral_store()
  values = list(
    null = NULL, nan = NaN, inf = Inf, raw = as.raw(1:3), empty = list(),
    nested = list(x = list(1L, "two"), y = NULL), text = "héllo \U0001F600"
  )
  for (key in names(values)) ephemeral_set(a, "{key}" := values[[key]])
  ephemeral_set(a, "clé" = TRUE)
  ephemeral_apply(b, ephemeral_encode(a))

  for (key in names(values)) expect_identical(ephemeral_get(b, key), values[[key]])
  expect_identical(ephemeral_get(b, "clé"), TRUE)

  events = 0
  sub = ephemeral_subscribe(a, function(event) events <<- events + 1)
  on.exit(unsubscribe(sub))
  ephemeral_delete(a, "never set")
  expect_identical(events, 0)
})
