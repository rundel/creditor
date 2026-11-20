# Trees

A tree is a hierarchy of nodes, such as an outline or a folder
structure. Each node has an id, a position among its siblings, and a
metadata map for its contents. Moving a node carries its whole subtree,
and concurrent moves merge without creating cycles or duplicate nodes.

- `tree_create()` creates a node, optionally with initial metadata, and
  returns its id.

- `tree_move()` moves a node, with its subtree, to a new parent or
  position.

- `tree_delete()` deletes a node and its descendants.

- `tree_meta()` returns the node's metadata as a map handle (the
  metadata of a deleted node can still be read, but not changed), to be
  used with
  [`map_set()`](https://rundel.github.io/creditor/reference/map.md),
  [`map_get()`](https://rundel.github.io/creditor/reference/map.md), and
  the other `map_*` functions.

- `tree_children()` returns the ids of a node's children in order, or of
  the root nodes when `parent` is `NULL`.

- `tree_nodes()` returns a data frame of all nodes with columns `id`,
  `parent` (`NA` for root nodes), and `index` (the 1-based position
  among siblings).

- `tree_contains()` reports whether a node exists and has not been
  deleted.

Node ids are strings of the form `"counter@peer"`. They are stable and
identical on every replica. A deleted node is gone for good, though:
when [`undo()`](https://rundel.github.io/creditor/reference/undo.md) or
[`doc_revert_to()`](https://rundel.github.io/creditor/reference/history.md)
brings back a deleted subtree, the nodes return with their structure and
metadata but under new ids, so ids held from before the deletion no
longer refer to anything. Undoing a move, and
[`doc_checkout()`](https://rundel.github.io/creditor/reference/history.md),
keep ids.

## Usage

``` r
tree_create(tree, parent = NULL, index = NULL, meta = list())

tree_move(tree, node, parent = NULL, index = NULL)

tree_delete(tree, node)

tree_meta(tree, node)

tree_children(tree, parent = NULL)

tree_nodes(tree)

tree_contains(tree, node)
```

## Arguments

- tree:

  A tree handle, from
  [`doc_tree()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container. A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  is also accepted and stands for its default root container; see
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md).

- parent:

  The id of the parent node, or `NULL` for the top level.

- index:

  A 1-based position among the parent's children, or `NULL` to place the
  node last. For a move it is the position the node ends up at.

- meta:

  A named list of plain values to store in the new node's metadata map,
  as [`map_set()`](https://rundel.github.io/creditor/reference/map.md)
  would.

- node:

  A node id.

## Value

`tree_create()` returns the new node id. `tree_move()` and
`tree_delete()` return `tree` invisibly. `tree_meta()` returns a map
handle, `tree_children()` a character vector, `tree_nodes()` a data
frame, and `tree_contains()` a logical.

## Examples

``` r
doc = loro_doc()
tree = doc_tree(doc, "outline")

intro = tree_create(tree, meta = list(title = "Introduction"))
methods = tree_create(tree, meta = list(title = "Methods"))
data = tree_create(tree, parent = intro, meta = list(title = "Data"))

tree_move(tree, data, parent = methods)
tree_meta(tree, data)$title
#> [1] "Data"
tree_nodes(tree)
#>                       id                 parent index
#> 1 0@15348026267880055746                   <NA>     1
#> 2 2@15348026267880055746                   <NA>     2
#> 3 4@15348026267880055746 2@15348026267880055746     1
tree_children(tree, methods)
#> [1] "4@15348026267880055746"
```
