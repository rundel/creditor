# Edit lists

A list is an ordered sequence of values. Positions are 1-based.
Concurrent insertions at the same position are all kept, in the same
order on every replica.

- `list_insert()` inserts values before the element currently at `pos`,
  and `list_push()` appends them. Each argument in `...` becomes one
  element, and can be a plain value or a new container from
  [`loro_text()`](https://rundel.github.io/creditor/reference/loro_text.md),
  [`loro_map()`](https://rundel.github.io/creditor/reference/loro_text.md),
  [`loro_list()`](https://rundel.github.io/creditor/reference/loro_text.md),
  and the like.

- `list_get()` returns the element at `pos`, as a handle if it is a
  container.

- `list_delete()` removes the elements at the positions `pos`, and
  `list_clear()` removes them all.

- `list_pop()` removes the last element and returns it, or returns
  `NULL` if the list is empty. A removed child container is returned as
  its contents.

- `list_length()` returns the number of elements.

A list handle also works with base functions: `list[[pos]]` reads like
`list_get()`, [`length()`](https://rdrr.io/r/base/length.html) is
`list_length()`, and [`as.list()`](https://rdrr.io/r/base/list.html) is
[`container_value()`](https://rundel.github.io/creditor/reference/containers.md).
`list[[pos]] = NULL` removes an element like `list_delete()`, and for a
movable list `list[[pos]] = value` replaces one like `list_set()`.

A movable list, from
[`doc_movable_list()`](https://rundel.github.io/creditor/reference/containers.md),
works with all of the functions above and adds two operations that merge
cleanly across replicas. In a plain list they can only be imitated by
deleting and re-inserting, which duplicates the element when two
replicas do it at once.

- `list_move()` moves the element at `from` so that it ends up at
  position `to`. Concurrent moves of one element leave a single copy.

- `list_set()` replaces the element at `pos` in place. Concurrent sets
  resolve to one winner.

Plain values are converted as described in the Values section of
[`map_set()`](https://rundel.github.io/creditor/reference/map.md).

## Usage

``` r
list_insert(list, pos, ...)

list_push(list, ...)

list_get(list, pos)

list_delete(list, pos)

list_length(list)

list_move(list, from, to)

list_set(list, pos, value)

list_pop(list)

list_clear(list)
```

## Arguments

- list:

  A list handle, from
  [`doc_list()`](https://rundel.github.io/creditor/reference/containers.md),
  [`doc_movable_list()`](https://rundel.github.io/creditor/reference/containers.md),
  or a parent container. `list_move()` and `list_set()` need a movable
  list. A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  is also accepted and stands for its default root list, which is a
  plain list, so it cannot be used with the functions that need a
  movable list; see
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md).

- pos:

  A 1-based position. For `list_delete()`, a vector of positions such as
  `2:4`.

- ...:

  Values to add, one element each: plain values or new containers. They
  must not be named; to store a map as one element, pass a named list or
  a
  [`loro_map()`](https://rundel.github.io/creditor/reference/loro_text.md).
  These are [dynamic
  dots](https://rlang.r-lib.org/reference/dyn-dots.html), so a list of
  elements can be spliced in with `!!!`.

- from, to:

  1-based positions.

- value:

  A plain value or a new container.

## Value

`list_insert()`, `list_push()`, `list_delete()`, `list_clear()`,
`list_move()`, and `list_set()` return `list` invisibly. `list_pop()`
returns the removed element. `list_get()` returns a value or handle, and
`list_length()` an integer.

## Examples

``` r
doc = loro_doc()
items = doc_list(doc, "items")
list_push(items, "b", "c")
list_insert(items, 1, "a")

list_push(items, loro_map(task = "d", done = FALSE))

list_get(items, 1)
#> [1] "a"
items[[2]]
#> [1] "b"
list_delete(items, 2:3)
as.list(items)
#> [[1]]
#> [1] "a"
#> 
#> [[2]]
#> [[2]]$done
#> [1] FALSE
#> 
#> [[2]]$task
#> [1] "d"
#> 
#> 

tasks = doc_movable_list(doc, "tasks")
list_push(tasks, "write", "test", "ship")
list_move(tasks, 3, 1)
list_set(tasks, 2, "write docs")
as.list(tasks)
#> [[1]]
#> [1] "ship"
#> 
#> [[2]]
#> [1] "write docs"
#> 
#> [[3]]
#> [1] "test"
#> 
```
