latin1 = function() iconv("café", "UTF-8", "latin1")
invalid = function() rawToChar(as.raw(c(0x61, 0xff)))

test_that("strings in another encoding are stored as UTF-8", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  text = doc_text(doc, "t")

  map_set(map, "value", latin1())
  map_set(map, "named", stats::setNames(list(1L), latin1()))
  map_set(map, "nested", list(list(latin1())))
  map_set(map, latin1(), TRUE)
  text_insert(text, 1, latin1())
  text_apply_delta(text, list(list(insert = latin1())))
  text_mark(text, 1, 2, "link", latin1())

  expect_identical(map_get(map, "value"), "café")
  expect_identical(names(map_get(map, "named")), "café")
  expect_identical(map_get(map, "nested"), list(list("café")))
  expect_true("café" %in% map_keys(map))
  expect_identical(text_get(text), "cafécafé")
  expect_identical(text_delta(text)[[1]]$attributes$link, "café")

  copy = loro_doc()
  doc_import(copy, doc_export(doc, "snapshot"))
  expect_identical(doc_value(copy), doc_value(doc))
})

test_that("strings that are not valid UTF-8 are rejected everywhere", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  text = doc_text(doc, "t")
  text_insert(text, 1, "abc")
  bytes = "abc"
  Encoding(bytes) = "bytes"

  expect_error(map_set(map, "k", invalid()), "UTF-8")
  expect_error(map_set(map, "k", list(a = list(invalid()))), "UTF-8")
  expect_error(map_set(map, "k", stats::setNames(list(1), invalid())), "UTF-8")
  expect_error(map_set(map, invalid(), 1), "UTF-8")
  expect_error(list_push(doc_list(doc, "l"), invalid()), "UTF-8")
  expect_error(text_insert(text, 1, invalid()), "UTF-8")
  expect_error(text_update(text, invalid()), "UTF-8")
  expect_error(text_apply_delta(text, list(list(insert = invalid()))), "UTF-8")
  expect_error(text_mark(text, 1, 1, "link", invalid()), "UTF-8")
  expect_error(ephemeral_set(ephemeral_store(), "k", invalid()), "UTF-8")
  expect_error(doc_commit(doc, message = invalid()), "UTF-8")
  expect_error(doc_undo_manager(doc, exclude_origins = invalid()), "UTF-8")

  expect_identical(map_keys(map), character())
  expect_identical(text_get(text), "abc")
  expect_type(doc_export(doc, "snapshot"), "raw")
})

test_that("a name that is the string NA is a valid name", {
  map = doc_map(loro_doc())
  map_set(map, "NA", 1L)
  map_set(map, "list", list("NA" = 1L))
  map_set(map, "vector", c("NA" = 1L, b = 2L))
  expect_identical(map_get(map, "NA"), 1L)
  expect_identical(map_get(map, "list"), list("NA" = 1L))
  expect_identical(map_get(map, "vector"), list("NA" = 1L, b = 2L))

  expect_error(map_set(map, "x", stats::setNames(list(1, 2), c("a", NA))), "names")
  expect_error(map_set(map, "x", list(a = 1, 2)), "names")
})

test_that("nesting is limited instead of overflowing the stack", {
  map = doc_map(loro_doc())
  nested = function(depth) {
    x = 1L
    for (i in seq_len(depth)) x = list(x)
    x
  }

  map_set(map, "ok", nested(999))
  expect_identical(map_get(map, "ok"), nested(999))
  expect_error(map_set(map, "deep", nested(1001)), "1000 levels")
  expect_error(map_set(map, "deeper", nested(30000)), "1000 levels")
  expect_identical(map_keys(map), "ok")
})

test_that("numbers keep their value and type at the boundaries", {
  map = doc_map(loro_doc(peer_id = 1))
  values = list(
    int_max = .Machine$integer.max,
    int_min = -.Machine$integer.max,
    past_int = 2^31,
    big = 2^53,
    negative = -2^62,
    fraction = -0.5,
    nan = NaN,
    inf = Inf,
    neg_inf = -Inf
  )
  for (key in names(values)) map_set(map, key, values[[key]])

  expect_identical(container_value(map), values[order(names(values))])
  expect_type(map_get(map, "int_max"), "integer")
  expect_type(map_get(map, "past_int"), "double")

  map_set(map, "neg_zero", -0)
  expect_identical(1 / map_get(map, "neg_zero"), -Inf)
  map_set(map, "mixed", c(NaN, NA, 1))
  expect_identical(map_get(map, "mixed"), list(NaN, NULL, 1))
})

test_that("integers outside R's range are read as doubles", {
  doc = loro_doc()
  json = paste0(
    '{"schema_version":1,"start_version":{},"peers":["5"],"changes":[{"id":"0@0",',
    '"timestamp":0,"deps":[],"lamport":0,"msg":null,"ops":[',
    '{"container":"cid:root-m:Map","content":{"type":"insert","key":"big","value":2147483648},"counter":0},',
    '{"container":"cid:root-m:Map","content":{"type":"insert","key":"min","value":-2147483648},"counter":1},',
    '{"container":"cid:root-m:Map","content":{"type":"insert","key":"fits","value":-2147483647},"counter":2}',
    ']}]}'
  )
  doc_import_json(doc, json)
  map = doc_map(doc, "m")
  expect_identical(map_get(map, "big"), 2147483648)
  expect_identical(map_get(map, "min"), -2147483648)
  expect_identical(map_get(map, "fits"), -2147483647L)
})

test_that("empty vectors and nulls convert predictably", {
  map = doc_map(loro_doc())
  for (empty in list(logical(), integer(), numeric(), character(), list())) {
    map_set(map, "v", empty)
    expect_identical(map_get(map, "v"), list())
  }
  map_set(map, "v", raw())
  expect_identical(map_get(map, "v"), raw())

  for (missing in list(NULL, NA, NA_integer_, NA_real_, NA_character_)) {
    map_set(map, "v", missing)
    expect_null(map_get(map, "v"))
    expect_identical(map_keys(map), "v")
  }

  nested = list(NULL, list(NULL), list(a = NULL), raw(), as.raw(0))
  map_set(map, "v", nested)
  expect_identical(map_get(map, "v"), nested)
})

test_that("an empty named list is stored as an empty list", {
  map = doc_map(loro_doc())
  map_set(map, "v", stats::setNames(list(), character()))
  expect_identical(map_get(map, "v"), list())
})

test_that("names on raw vectors and other attributes are dropped", {
  map = doc_map(loro_doc())
  map_set(map, "raw", c(a = as.raw(1)))
  expect_identical(map_get(map, "raw"), as.raw(1))
  map_set(map, "matrix", matrix(1:4, 2))
  expect_identical(map_get(map, "matrix"), list(1L, 2L, 3L, 4L))
  expect_error(map_set(map, "x", 1i), "can be stored")
  expect_error(map_set(map, "x", quote(a)), "can be stored")
  expect_error(map_set(map, "x", list(1, list(mean))), "can be stored")
  expect_identical(map_keys(map), c("matrix", "raw"))
})

test_that("unusual keys and long strings round trip", {
  doc = loro_doc(peer_id = 1)
  map = doc_map(doc, "m")
  keys = c("a b", "é", "\U0001F600", "a.b", "$x", "a/b", "")
  for (key in keys) map_set(map, key, key)
  for (key in keys) expect_identical(map_get(map, key), key)

  special = "line\nbreak\ttab \"quote\" back\\slash cid:root-x:Map"
  map_set(map, "special", special)
  long = strrep("abcdefghij", 100000)
  map_set(map, "long", long)

  copy = loro_doc()
  doc_import(copy, doc_export(doc, "snapshot"))
  expect_identical(map_get(doc_map(copy, "m"), "special"), special)
  expect_identical(map_get(doc_map(copy, "m"), "long"), long)
  expect_identical(map_get(doc_map(copy, "m"), ""), "")
})

test_that("map keys are in byte order", {
  map = doc_map(loro_doc())
  keys = c("b", "B", "a", "_z", "10", "9")
  for (key in keys) map_set(map, key, 1L)
  expect_identical(map_keys(map), sort(keys, method = "radix"))
  expect_identical(names(container_value(map)), sort(keys, method = "radix"))
})
