outline = function() {
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "t")
  a = tree_create(tree)
  b = tree_create(tree)
  a1 = tree_create(tree, parent = a)
  a2 = tree_create(tree, parent = a)
  list(doc = doc, tree = tree, a = a, b = b, a1 = a1, a2 = a2)
}

test_that("an empty tree has no nodes", {
  tree = doc_tree(loro_doc(), "t")
  expect_s3_class(tree, "creditor::loro_tree")
  expect_identical(container_id(tree), "cid:root-t:Tree")
  expect_identical(tree_children(tree), character())
  expect_identical(
    tree_nodes(tree),
    tibble::tibble(id = character(), parent = character(), index = integer())
  )
  expect_identical(container_value(tree), list())
})

test_that("nodes are created under parents in order", {
  o = outline()
  expect_identical(c(o$a, o$b, o$a1, o$a2), c("0@1", "1@1", "2@1", "3@1"))
  expect_identical(tree_children(o$tree), c(o$a, o$b))
  expect_identical(tree_children(o$tree, o$a), c(o$a1, o$a2))
  expect_identical(tree_children(o$tree, o$b), character())

  first = tree_create(o$tree, index = 1)
  middle = tree_create(o$tree, parent = o$a, index = 2)
  expect_identical(tree_children(o$tree), c(first, o$a, o$b))
  expect_identical(tree_children(o$tree, o$a), c(o$a1, middle, o$a2))
})

test_that("tree_nodes lists every node with parent and position", {
  o = outline()
  nodes = tree_nodes(o$tree)
  nodes = nodes[order(nodes$id), ]
  rownames(nodes) = NULL
  expect_identical(
    nodes,
    tibble::tibble(
      id = c(o$a, o$b, o$a1, o$a2),
      parent = c(NA, NA, o$a, o$a),
      index = c(1L, 2L, 1L, 2L)
    )
  )
})

test_that("nodes carry metadata maps", {
  o = outline()
  meta = tree_meta(o$tree, o$a)
  expect_s3_class(meta, "creditor::loro_map")
  map_set(meta, title = "Intro")
  body = loro_text()
  map_set(meta, body = body)
  text_insert(body, 1, "Hello")

  expect_identical(map_get(tree_meta(o$tree, o$a), "title"), "Intro")
  expect_identical(text_get(map_get(tree_meta(o$tree, o$a), "body")), "Hello")
  expect_identical(map_keys(tree_meta(o$tree, o$b)), character())

  value = container_value(o$tree)
  expect_identical(value[[1]]$id, o$a)
  expect_identical(value[[1]]$meta, list(body = "Hello", title = "Intro"))
  expect_length(value[[1]]$children, 2)
})

test_that("a move carries the subtree", {
  o = outline()
  tree_move(o$tree, o$a, parent = o$b)
  expect_identical(tree_children(o$tree), o$b)
  expect_identical(tree_children(o$tree, o$b), o$a)
  expect_identical(tree_children(o$tree, o$a), c(o$a1, o$a2))

  tree_move(o$tree, o$a2)
  expect_identical(tree_children(o$tree), c(o$b, o$a2))
  tree_move(o$tree, o$a2, index = 1)
  expect_identical(tree_children(o$tree), c(o$a2, o$b))
  tree_move(o$tree, o$a2, parent = o$a, index = 1)
  expect_identical(tree_children(o$tree, o$a), c(o$a2, o$a1))
})

test_that("a move that would create a cycle is an error", {
  o = outline()
  expect_error(tree_move(o$tree, o$a, parent = o$a1), "Cycle")
  expect_error(tree_move(o$tree, o$a, parent = o$a), "Cycle")
  expect_identical(tree_children(o$tree), c(o$a, o$b))
})

test_that("deleting a node removes its subtree", {
  o = outline()
  tree_delete(o$tree, o$a)
  expect_identical(tree_children(o$tree), o$b)
  expect_identical(tree_nodes(o$tree)$id, o$b)
  expect_false(tree_contains(o$tree, o$a))
  expect_false(tree_contains(o$tree, o$a1))
  expect_true(tree_contains(o$tree, o$b))
  expect_false(tree_contains(o$tree, "99@99"))
})

test_that("deleted and unknown nodes are rejected", {
  o = outline()
  tree_delete(o$tree, o$a)
  expect_error(tree_create(o$tree, parent = o$a), "deleted")
  expect_error(tree_move(o$tree, o$b, parent = o$a), "deleted")
  expect_error(tree_children(o$tree, o$a), "deleted")
  expect_error(tree_delete(o$tree, o$a), "deleted")
  expect_error(tree_move(o$tree, o$a), "deleted")
  expect_error(tree_create(o$tree, parent = "99@99"), "does not exist")
  expect_error(tree_meta(o$tree, "99@99"), "exist")
  expect_identical(tree_children(o$tree), o$b)
})

test_that("tree arguments are validated", {
  o = outline()
  expect_error(tree_create(doc_map(o$doc)), "loro_tree")
  expect_error(tree_create(o$tree, parent = "a"), "parent")
  expect_error(tree_create(o$tree, parent = 1), "parent")
  expect_error(tree_create(o$tree, index = 0), "index")
  expect_error(tree_create(o$tree, index = 99))
  expect_error(tree_move(o$tree, "nope"), "node")
  expect_error(tree_move(o$tree, o$a, index = 99))
  expect_error(tree_delete(o$tree, NA_character_), "node")
  expect_identical(nrow(tree_nodes(o$tree)), 4L)
})

test_that("concurrent moves converge without cycles", {
  o = outline()
  other = loro_doc(peer_id = 2)
  doc_import(other, doc_export(o$doc))
  other_tree = doc_tree(other, "t")

  tree_move(o$tree, o$a, parent = o$b)
  tree_move(other_tree, o$b, parent = o$a)
  doc_import(other, doc_export_updates(o$doc))
  doc_import(o$doc, doc_export_updates(other))

  mine = tree_nodes(o$tree)
  theirs = tree_nodes(other_tree)
  expect_identical(mine[order(mine$id), ], theirs[order(theirs$id), ])
  expect_setequal(mine$id, c(o$a, o$b, o$a1, o$a2))
  expect_length(tree_children(o$tree), 1)
})

test_that("concurrent metadata edits merge", {
  o = outline()
  other = loro_doc(peer_id = 2)
  doc_import(other, doc_export(o$doc))

  map_set(tree_meta(o$tree, o$a), title = "Intro")
  map_set(tree_meta(doc_tree(other, "t"), o$a), done = TRUE)
  doc_import(other, doc_export_updates(o$doc))
  doc_import(o$doc, doc_export_updates(other))

  expect_identical(
    container_value(tree_meta(o$tree, o$a)),
    list(done = TRUE, title = "Intro")
  )
  expect_identical(doc_value(o$doc), doc_value(other))
})

test_that("tree changes appear in diffs", {
  o = outline()
  v1 = doc_frontiers(o$doc)
  tree_move(o$tree, o$a2, parent = o$b)
  tree_delete(o$tree, o$a1)
  new = tree_create(o$tree)

  diff = doc_diff(o$doc, v1, doc_frontiers(o$doc))[["cid:root-t:Tree"]]
  expect_identical(diff$type, "tree")
  by_node = stats::setNames(diff$diff, vapply(diff$diff, `[[`, "", "node"))
  expect_identical(
    by_node[[o$a2]],
    list(
      node = o$a2, action = "move", parent = o$b, index = 1L,
      old_parent = o$a, old_index = 2L
    )
  )
  expect_identical(by_node[[o$a1]]$action, "delete")
  expect_identical(by_node[[o$a1]]$old_parent, o$a)
  expect_identical(
    by_node[[new]],
    list(node = new, action = "create", parent = NA_character_, index = 3L)
  )
})

test_that("checkout shows the tree at an earlier version", {
  o = outline()
  v1 = doc_frontiers(o$doc)
  tree_delete(o$tree, o$b)
  tree_move(o$tree, o$a2)

  doc_checkout(o$doc, v1)
  expect_identical(tree_children(o$tree), c(o$a, o$b))
  expect_identical(tree_children(o$tree, o$a), c(o$a1, o$a2))
  doc_checkout(o$doc)
  expect_identical(tree_children(o$tree), c(o$a, o$a2))
})

test_that("undoing a move restores the node in place", {
  o = outline()
  doc_commit(o$doc)
  manager = doc_undo_manager(o$doc)
  tree_move(o$tree, o$b, index = 1)
  doc_commit(o$doc)

  undo(manager)
  expect_identical(tree_children(o$tree), c(o$a, o$b))
})

test_that("undoing a delete restores the subtree under new ids", {
  o = outline()
  map_set(tree_meta(o$tree, o$a), title = "A")
  map_set(tree_meta(o$tree, o$a1), title = "A1")
  doc_commit(o$doc)
  manager = doc_undo_manager(o$doc)
  tree_delete(o$tree, o$a)
  doc_commit(o$doc)

  undo(manager)
  roots = tree_children(o$tree)
  expect_length(roots, 2)
  expect_identical(roots[2], o$b)
  expect_false(roots[1] %in% c(o$a, o$a1, o$a2))
  expect_false(tree_contains(o$tree, o$a))

  expect_identical(map_get(tree_meta(o$tree, roots[1]), "title"), "A")
  children = tree_children(o$tree, roots[1])
  expect_length(children, 2)
  expect_identical(map_get(tree_meta(o$tree, children[1]), "title"), "A1")
})

test_that("a tree can be nested and prints its nodes", {
  doc = loro_doc(peer_id = 1)
  tree = loro_tree()
  map_set(doc_map(doc, "m"), outline = tree)
  expect_s3_class(tree, "creditor::loro_tree")
  node = tree_create(tree)
  expect_s3_class(map_get(doc_map(doc, "m"), "outline"), "creditor::loro_tree")

  out = utils::capture.output(invisible(cli::cli_fmt(print(tree))))
  expect_match(paste(out, collapse = "\n"), node, fixed = TRUE)
})

test_that("tree values use 1-based positions and NA root parents", {
  o = outline()
  map_set(tree_meta(o$tree, o$a2), title = "second child")
  value = container_value(o$tree)

  expect_length(value, 2)
  expect_named(value[[1]], c("id", "parent", "index", "fractional_index", "meta", "children"))
  expect_identical(vapply(value, `[[`, "", "id"), c(o$a, o$b))
  expect_identical(vapply(value, `[[`, 1L, "index"), c(1L, 2L))
  expect_identical(value[[1]]$parent, NA_character_)
  expect_type(value[[1]]$fractional_index, "character")

  kids = value[[1]]$children
  expect_identical(vapply(kids, `[[`, "", "id"), c(o$a1, o$a2))
  expect_identical(vapply(kids, `[[`, 1L, "index"), c(1L, 2L))
  expect_identical(kids[[2]]$parent, o$a)
  expect_identical(kids[[2]]$meta, list(title = "second child"))
  expect_identical(kids[[2]]$children, list())

  expect_identical(doc_value(o$doc)$t, value)
  nodes = tree_nodes(o$tree)
  expect_identical(nodes$index[match(o$a2, nodes$id)], kids[[2]]$index)
})

test_that("a shallow tree value gives metadata maps by id", {
  o = outline()
  shallow = container_value(o$tree, deep = FALSE)
  expect_identical(shallow[[1]]$meta, container_id(tree_meta(o$tree, o$a)))
  expect_identical(shallow[[1]]$children[[1]]$id, o$a1)
})

test_that("a map entry named index is not mistaken for a tree position", {
  doc = loro_doc()
  map = doc_map(doc, "m")
  map_set(map, index = 0L)
  map_set(map, node = list(id = "0@1", index = 0L, parent = NULL))
  expect_identical(
    doc_value(doc)$m,
    list(index = 0L, node = list(id = "0@1", index = 0L, parent = NULL))
  )
})

test_that("nodes inside a deleted subtree cannot be moved or deleted", {
  o = outline()
  tree_delete(o$tree, o$a)
  expect_false(tree_contains(o$tree, o$a1))

  expect_error(tree_move(o$tree, o$a1), "deleted")
  expect_error(tree_move(o$tree, o$a1, parent = o$b), "deleted")
  expect_error(tree_delete(o$tree, o$a1), "deleted")
  expect_identical(tree_nodes(o$tree)$id, o$b)
  expect_false(tree_contains(o$tree, o$a1))
})

test_that("the metadata of a deleted node can be read but not changed", {
  o = outline()
  meta = tree_meta(o$tree, o$a1)
  map_set(meta, x = 1L)
  tree_delete(o$tree, o$a)

  expect_identical(map_get(meta, "x"), 1L)
  expect_identical(map_get(tree_meta(o$tree, o$a1), "x"), 1L)
  expect_error(map_set(meta, y = 2L), "deleted")
  expect_error(tree_meta(o$tree, "5@1"), "node 5@1 does not exist")
})

test_that("index errors use the 1-based position given", {
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "t")
  ids = vapply(1:5, function(i) tree_create(tree), character(1))

  expect_error(tree_create(tree, index = 7), "at most 6, not 7")
  expect_error(tree_move(tree, ids[1], index = 6), "at most 5, not 6")
  expect_error(tree_move(tree, ids[2], parent = ids[1], index = 2), "at most 1, not 2")
  expect_identical(tree_children(tree), ids)

  last = tree_create(tree, index = 6)
  expect_identical(tree_children(tree), c(ids, last))
})

test_that("a move within one parent ends at the index given", {
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "t")
  ids = vapply(1:5, function(i) tree_create(tree), character(1))

  tree_move(tree, ids[1], index = 3)
  expect_identical(tree_children(tree), ids[c(2, 3, 1, 4, 5)])
  tree_move(tree, ids[1], index = 1)
  expect_identical(tree_children(tree), ids)
  tree_move(tree, ids[1], index = 5)
  expect_identical(tree_children(tree), ids[c(2, 3, 4, 5, 1)])
  tree_move(tree, ids[5], index = 2)
  expect_identical(tree_children(tree), ids[c(2, 5, 3, 4, 1)])
})

test_that("order holds up across many random inserts and moves", {
  set.seed(1)
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "t")
  expected = character()
  for (i in 1:200) {
    index = sample.int(length(expected) + 1, 1)
    expected = append(expected, tree_create(tree, index = index), after = index - 1)
  }
  for (i in 1:200) {
    from = sample.int(length(expected), 1)
    to = sample.int(length(expected), 1)
    node = expected[from]
    tree_move(tree, node, index = to)
    expected = append(expected[-from], node, after = to - 1)
  }

  expect_identical(tree_children(tree), expected)
  nodes = tree_nodes(tree)
  expect_identical(nodes$id[order(nodes$index)], expected)
  value = container_value(tree)
  expect_identical(vapply(value, `[[`, "", "id"), expected)
  expect_identical(vapply(value, `[[`, 1L, "index"), seq_along(expected))

  copy = loro_doc()
  doc_import(copy, doc_export(doc))
  expect_identical(tree_children(doc_tree(copy, "t")), expected)
  expect_identical(tree_children(doc_tree(doc_fork(doc), "t")), expected)
})

test_that("a concurrent delete of an ancestor and move of a descendant converge", {
  a = loro_doc(peer_id = 1)
  tree = doc_tree(a, "t")
  root = tree_create(tree)
  keep = tree_create(tree, parent = root)
  doomed = tree_create(tree, parent = root)
  moved = tree_create(tree, parent = doomed)
  b = loro_doc(peer_id = 2)
  doc_import(b, doc_export(a))

  tree_delete(tree, doomed)
  tree_move(doc_tree(b, "t"), moved, parent = keep)
  doc_import(b, doc_export_updates(a))
  doc_import(a, doc_export_updates(b))

  expect_identical(doc_value(a), doc_value(b))
  expect_false(tree_contains(tree, doomed))
  expect_true(tree_contains(tree, moved))
  expect_identical(tree_children(tree, keep), moved)
})

test_that("a very deep tree can be built and listed but not expanded", {
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "t")
  parent = NULL
  for (i in 1:1500) parent = tree_create(tree, parent = parent)

  expect_identical(nrow(tree_nodes(tree)), 1500L)
  expect_error(container_value(tree), "1000 levels")
  expect_error(doc_value(doc), "1000 levels")

  copy = loro_doc()
  doc_import(copy, doc_export(doc))
  expect_identical(nrow(tree_nodes(doc_tree(copy, "t"))), 1500L)
  tree_delete(tree, tree_children(tree))
  expect_identical(nrow(tree_nodes(tree)), 0L)
})

test_that("redoing a create brings the node back under a new id", {
  doc = loro_doc(peer_id = 1)
  tree = doc_tree(doc, "t")
  manager = doc_undo_manager(doc)
  node = tree_create(tree)
  doc_commit(doc)

  undo(manager)
  expect_identical(tree_children(tree), character())
  redo(manager)
  expect_length(tree_children(tree), 1)
  expect_false(tree_contains(tree, node))
})

test_that("node ids from elsewhere and malformed ids are rejected", {
  doc = loro_doc(peer_id = 1)
  one = doc_tree(doc, "one")
  two = doc_tree(doc, "two")
  node = tree_create(one)

  expect_false(tree_contains(two, node))
  expect_error(tree_move(two, node), "does not exist")
  expect_error(tree_delete(two, node), "does not exist")
  expect_error(tree_create(two, parent = node), "does not exist")
  expect_error(tree_contains(one, "99999999999999999999@1"), "not a valid node id")
  expect_error(tree_contains(one, "-1@1"), "node")
  expect_identical(tree_children(one), node)
})

test_that("a node can be created with metadata", {
  tree = doc_tree(loro_doc())
  node = tree_create(tree, meta = list(title = "Intro", tags = c("a", "b")))
  expect_identical(as.list(tree_meta(tree, node)), list(tags = list("a", "b"), title = "Intro"))
  expect_identical(length(tree_meta(tree, tree_create(tree))), 0L)
  expect_error(tree_create(tree, meta = list(1)), "named")
  expect_error(tree_create(tree, meta = "title"), "named list")
})
