test_that("new containers hold their initial contents before they are stored", {
  expect_identical(container_value(loro_text("hi")), "hi")
  expect_identical(container_value(loro_text()), "")
  expect_identical(container_value(loro_map(a = 1, b = "x")), list(a = 1, b = "x"))
  expect_identical(container_value(loro_list("a", 2L)), list("a", 2L))
  expect_identical(container_value(loro_movable_list("a", "b")), list("a", "b"))
  expect_identical(container_value(loro_counter(5)), 5)
  expect_identical(nrow(tree_nodes(loro_tree())), 0L)

  expect_true(S7::S7_inherits(loro_movable_list(), loro_list))
  expect_message(print(loro_text("hi")), "not yet in a document")
})

test_that("new containers can be edited before they are stored", {
  text = loro_text("hi")
  text_insert(text, 3, " there")
  list = loro_movable_list("a", "b")
  list_move(list, 2, 1)
  counter = loro_counter()
  counter_increment(counter, 2)

  doc = loro_doc()
  map_set(doc, text = text, list = list, counter = counter)
  expect_identical(
    doc_value(doc)$map,
    list(counter = 2, list = list("b", "a"), text = "hi there")
  )
})

test_that("new containers can be stored wherever a value can", {
  doc = loro_doc()
  note = doc_map(doc, "note")
  note$a = loro_text("a")
  note[["b"]] = loro_text("b")
  map_set(note, c = loro_text("c"))

  items = doc_list(doc, "items")
  list_push(items, loro_text("2"))
  list_insert(items, 1, loro_text("1"))

  moves = doc_movable_list(doc, "moves")
  list_push(moves, "x", "y")
  list_set(moves, 1, loro_text("x2"))
  moves[[2]] = loro_list("y2")

  value = doc_value(doc)
  expect_identical(value$note, list(a = "a", b = "b", c = "c"))
  expect_identical(value$items, list("1", "2"))
  expect_identical(value$moves, list("x2", list("y2")))
  expect_s3_class(note$a, "creditor::loro_text")
  expect_s3_class(moves[[2]], "creditor::loro_list")
})

test_that("new containers nest", {
  doc = loro_doc()
  map_set(doc, todo = loro_list(
    loro_map(task = "write", tags = loro_list("a", "b")),
    loro_map(task = "test", note = loro_text("soon"))
  ))
  expect_identical(
    doc_value(doc)$map$todo,
    list(
      list(tags = list("a", "b"), task = "write"),
      list(note = "soon", task = "test")
    )
  )
  expect_identical(text_get(doc_get(doc, "map", "todo", 2, "note")), "soon")
})

test_that("a stored handle, and handles nested in it, follow it into the document", {
  doc = loro_doc()
  note = doc_map(doc, "note")
  tags = loro_list("a")
  items = loro_map(tags = tags)
  note$items = items

  map_set(items, n = 1)
  list_push(tags, "b")
  expect_identical(doc_value(doc)$note$items, list(n = 1, tags = list("a", "b")))
  expect_identical(container_id(items), container_id(note$items))
  expect_identical(container_id(tags), container_id(note$items$tags))
  expect_no_message(capture.output(print(items)), message = "not yet")

  copy = loro_doc()
  doc_import(copy, doc_export(doc))
  expect_identical(doc_value(copy), doc_value(doc))
})

test_that("a container already in a document cannot be stored again", {
  doc = loro_doc()
  note = doc_map(doc, "note")
  items = loro_list("a")
  note$items = items

  expect_error(note$again <- items, "cannot be stored again")
  expect_error(map_set(note, again = items), "cannot be stored again")
  expect_error(list_push(doc_list(doc, "l"), items), "cannot be stored again")
  expect_error(list_push(doc_list(doc, "l"), doc_text(doc)), "cannot be stored again")

  note$items = items
  expect_identical(doc_value(doc)$note$items, list("a"))
})

test_that("storing a new container is one undoable edit that reaches subscribers", {
  doc = loro_doc()
  manager = doc_undo_manager(doc)
  events = list()
  sub = doc_subscribe(doc, function(event) events[[length(events) + 1]] <<- event)
  on.exit(unsubscribe(sub))

  map_set(doc, items = loro_list("a", "b"))
  doc_commit(doc)
  expect_length(events, 1)
  expect_identical(doc_value(doc)$map$items, list("a", "b"))

  undo(manager)
  expect_identical(doc_value(doc)$map, setNames(list(), character()))
})

test_that("constructor arguments are checked", {
  expect_error(loro_text(1:2), "single string")
  expect_error(loro_map(1), "named")
  expect_error(loro_list(a = 1), "must not be named")
  expect_error(loro_counter("a"), "number")
})
