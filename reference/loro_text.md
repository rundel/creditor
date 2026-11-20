# Create containers

These functions create a container that does not yet belong to a
document. Store it in a map or list, the way a nested list is built in
R, and it becomes part of that document:

    note = doc_map(doc, "note")
    note$items = loro_list("milk", "eggs")
    note$body = loro_text("Buy before Friday")

Containers nest, so `loro_map(title = "Notes", tags = loro_list("a"))`
builds a map holding a list, and all of it is added in one step when it
is stored. Wherever a value can be stored
([`map_set()`](https://rundel.github.io/creditor/reference/map.md),
`$<-` and `[[<-` on a map,
[`list_insert()`](https://rundel.github.io/creditor/reference/list.md),
[`list_push()`](https://rundel.github.io/creditor/reference/list.md),
[`list_set()`](https://rundel.github.io/creditor/reference/list.md), and
`[[<-` on a list), a new container can be given instead.

A new container can be edited with the usual functions before it is
stored. Storing it adds a copy of its contents to the document, and from
then on the handle, and any handle to a container nested in it, refers
to the container in the document, so later edits through it are part of
the document's history and sync like any other.

A container can be stored only once. Storing a handle to a container
that is already in a document is an error, except for assigning a child
back to the key it was read from (as in `map$child$key = value`), which
does nothing.

The objects returned are the handle classes described in
[`containers`](https://rundel.github.io/creditor/reference/containers.md).

## Usage

``` r
loro_text(value = "", .ptr = NULL)

loro_map(..., .ptr = NULL)

loro_list(..., .ptr = NULL)

loro_movable_list(..., .ptr = NULL)

loro_counter(value = 0, .ptr = NULL)

loro_tree(.ptr = NULL)
```

## Arguments

- value:

  For `loro_text()`, the initial text, a string. For `loro_counter()`,
  the initial value, a number.

- .ptr:

  For internal use.

- ...:

  For `loro_map()`, values named by key, as in
  [`map_set()`](https://rundel.github.io/creditor/reference/map.md). For
  `loro_list()` and `loro_movable_list()`, unnamed elements, as in
  [`list_push()`](https://rundel.github.io/creditor/reference/list.md).
  Values may themselves be new containers.

## Value

A container handle that does not belong to a document until it is
stored.

## Examples

``` r
doc = loro_doc()
note = doc_map(doc, "note")

note$title = "Groceries"
note$items = loro_list("milk", "eggs")
note$body = loro_text("Buy before Friday")
str(doc_value(doc))
#> List of 1
#>  $ note:List of 3
#>   ..$ body : chr "Buy before Friday"
#>   ..$ items:List of 2
#>   .. ..$ : chr "milk"
#>   .. ..$ : chr "eggs"
#>   ..$ title: chr "Groceries"

list_push(note$items, "bread")
text_push(note$body, "!")

map_set(doc, todo = loro_list(
  loro_map(task = "write", done = TRUE),
  loro_map(task = "test", done = FALSE)
))
doc_get(doc, "map", "todo", 2, "task")
#> [1] "test"
```
