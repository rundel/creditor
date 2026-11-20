#' Trees
#'
#' @description
#' A tree is a hierarchy of nodes, such as an outline or a folder
#' structure. Each node has an id, a position among its siblings, and a
#' metadata map for its contents. Moving a node carries its whole
#' subtree, and concurrent moves merge without creating cycles or
#' duplicate nodes.
#'
#' * `tree_create()` creates a node and returns its id.
#' * `tree_move()` moves a node, with its subtree, to a new parent or
#'   position.
#' * `tree_delete()` deletes a node and its descendants.
#' * `tree_meta()` returns the node's metadata as a map handle (the
#'   metadata of a deleted node can still be read, but not changed), to be
#'   used with [`map_set()`], [`map_get()`], and the other `map_*`
#'   functions.
#' * `tree_children()` returns the ids of a node's children in order,
#'   or of the root nodes when `parent` is `NULL`.
#' * `tree_nodes()` returns a data frame of all nodes with columns
#'   `id`, `parent` (`NA` for root nodes), and `index` (the 1-based
#'   position among siblings).
#' * `tree_contains()` reports whether a node exists and has not been
#'   deleted.
#'
#' Node ids are strings of the form `"counter@peer"`. They are stable
#' and identical on every replica. A deleted node is gone for good,
#' though: when [`undo()`] or [`doc_revert_to()`] brings back a deleted
#' subtree, the nodes return with their structure and metadata but
#' under new ids, so ids held from before the deletion no longer refer
#' to anything. Undoing a move, and [`doc_checkout()`], keep ids.
#'
#' @param tree A tree handle, from [`doc_tree()`] or a parent container.
#' @param node A node id.
#' @param parent The id of the parent node, or `NULL` for the top level.
#' @param index A 1-based position among the parent's children, or
#'   `NULL` to place the node last. For a move it is the position the
#'   node ends up at.
#'
#' @return `tree_create()` returns the new node id. `tree_move()` and
#'   `tree_delete()` return `tree` invisibly. `tree_meta()` returns a map
#'   handle, `tree_children()` a character vector, `tree_nodes()` a data
#'   frame, and `tree_contains()` a logical.
#'
#' @examples
#' doc = loro_doc()
#' tree = doc_tree(doc, "outline")
#'
#' intro = tree_create(tree)
#' map_set(tree_meta(tree, intro), "title", "Introduction")
#' methods = tree_create(tree)
#' map_set(tree_meta(tree, methods), "title", "Methods")
#' data = tree_create(tree, parent = intro)
#' map_set(tree_meta(tree, data), "title", "Data")
#'
#' tree_move(tree, data, parent = methods)
#' tree_nodes(tree)
#' tree_children(tree, methods)
#'
#' @name tree
NULL

check_node = function(node, arg, call = sys.call(-1)) {
  if (!is.character(node) || length(node) != 1 || is.na(node) || !grepl("^[0-9]+@[0-9]+$", node)) {
    cli::cli_abort(
      "{.arg {arg}} must be a node id such as {.val 0@1}, from {.fn tree_create}.",
      call = call
    )
  }
  node
}

check_parent = function(parent, call = sys.call(-1)) {
  if (is.null(parent)) {
    return(NULL)
  }
  check_node(parent, "parent", call = call)
}

check_index = function(index, call = sys.call(-1)) {
  if (is.null(index)) {
    return(NULL)
  }
  check_count(index, "index", 1, call = call) - 1L
}

#' @rdname tree
#' @export
tree_create = function(tree, parent = NULL, index = NULL) {
  check_container(tree, loro_tree, "tree")
  loro_tree_create_impl(tree@ptr, check_parent(parent), check_index(index))
}

#' @rdname tree
#' @export
tree_move = function(tree, node, parent = NULL, index = NULL) {
  check_container(tree, loro_tree, "tree")
  node = check_node(node, "node")
  loro_tree_move_impl(tree@ptr, node, check_parent(parent), check_index(index))
  invisible(tree)
}

#' @rdname tree
#' @export
tree_delete = function(tree, node) {
  check_container(tree, loro_tree, "tree")
  loro_tree_delete_impl(tree@ptr, check_node(node, "node"))
  invisible(tree)
}

#' @rdname tree
#' @export
tree_meta = function(tree, node) {
  check_container(tree, loro_tree, "tree")
  container_from_ref(loro_tree_meta_impl(tree@ptr, check_node(node, "node")))
}

#' @rdname tree
#' @export
tree_children = function(tree, parent = NULL) {
  check_container(tree, loro_tree, "tree")
  loro_tree_children_impl(tree@ptr, check_parent(parent))
}

#' @rdname tree
#' @export
tree_nodes = function(tree) {
  check_container(tree, loro_tree, "tree")
  nodes = loro_tree_nodes_impl(tree@ptr)
  data.frame(id = nodes$id, parent = nodes$parent, index = nodes$index + 1L)
}

#' @rdname tree
#' @export
tree_contains = function(tree, node) {
  check_container(tree, loro_tree, "tree")
  loro_tree_contains_impl(tree@ptr, check_node(node, "node"))
}
