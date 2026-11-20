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
    data.frame(id = character(), parent = character(), index = integer())
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
    data.frame(
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
  map_set(meta, "title", "Intro")
  body = map_set_container(meta, "body", "text")
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
  expect_error(tree_create(o$doc), "loro_tree")
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
  doc_import(other, doc_export(o$doc, "updates"))
  doc_import(o$doc, doc_export(other, "updates"))

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

  map_set(tree_meta(o$tree, o$a), "title", "Intro")
  map_set(tree_meta(doc_tree(other, "t"), o$a), "done", TRUE)
  doc_import(other, doc_export(o$doc, "updates"))
  doc_import(o$doc, doc_export(other, "updates"))

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
  map_set(tree_meta(o$tree, o$a), "title", "A")
  map_set(tree_meta(o$tree, o$a1), "title", "A1")
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
  tree = map_set_container(doc_map(doc, "m"), "outline", "tree")
  expect_s3_class(tree, "creditor::loro_tree")
  node = tree_create(tree)
  expect_s3_class(map_get(doc_map(doc, "m"), "outline"), "creditor::loro_tree")

  out = utils::capture.output(invisible(cli::cli_fmt(print(tree))))
  expect_match(paste(out, collapse = "\n"), node, fixed = TRUE)
})
