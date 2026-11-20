# Edit maps

A map holds values under string keys. When replicas set the same key
concurrently, one write wins on every replica.

- `map_set()` stores values, given as `key = value` arguments. A value
  can be a plain R value or a new container from
  [`loro_text()`](https://rundel.github.io/creditor/reference/loro_text.md),
  [`loro_map()`](https://rundel.github.io/creditor/reference/loro_text.md),
  [`loro_list()`](https://rundel.github.io/creditor/reference/loro_text.md),
  and the like.

- `map_get()` returns the value under `key`, a handle if it is a
  container, or `NULL` if the key is absent.

- `map_has()` reports whether each of `keys` is present.

- `map_ensure_container()` returns the child container under `key`,
  creating it if the key is empty. Unlike storing a new container with
  `map_set()`, which always makes a fresh one, the container it creates
  is shared: replicas that each create it independently end up editing
  the same one, with all their edits merged. Use it for containers that
  are created lazily on first use. It is an error if `key` already holds
  a plain value, a container of another type, or a container stored with
  `map_set()`.

- `map_delete()` removes the keys named in `...`, as in
  `map_delete(map, "a", "b")` or `map_delete(map, keys)`, and
  `map_clear()` removes every key.

- `map_last_editor()` returns the peer id of the replica that last wrote
  `key`, or `NA` if the key has never been written.

- `map_keys()` returns the keys in sorted order, and `map_length()` the
  number of entries.

A map handle also works with the base functions an R user would reach
for with a named list: `map$key` and `map[[key]]` read like `map_get()`,
`map$key = value` and `map[[key]] = value` write one key like
`map_set()`, [`names()`](https://rdrr.io/r/base/names.html) is
`map_keys()`, [`length()`](https://rdrr.io/r/base/length.html) is
`map_length()`, and [`as.list()`](https://rdrr.io/r/base/list.html) is
[`container_value()`](https://rundel.github.io/creditor/reference/containers.md).
As with a list, assigning `NULL` removes the key: `map$key = NULL` is
`map_delete(map, "key")`. To store a null, use
`map_set(map, key = NULL)`. Assignments can reach through child
containers, as in `map$child$key = value`.

Loro allows the empty string as a key, and a document written by another
Loro client may contain one. It is supported only for compatibility with
such documents: it can be read and removed like any other key, but R
does not allow an empty argument name, so it cannot be written with
`map_set()`. Use `map[[""]] = value` if one has to be changed.

## Usage

``` r
map_set(.map, ...)

map_ensure_container(map, key, type)

map_get(map, key)

map_has(map, keys)

map_delete(map, ...)

map_clear(map)

map_keys(map)

map_length(map)

map_last_editor(map, key)
```

## Arguments

- .map:

  A map handle, as for `map`. For `map_set()` the argument name starts
  with a dot so that it cannot clash with a key given in `...`, such as
  `map_set(x, map = 1)`.

- ...:

  Values to store, each named with its key, for example
  `map_set(map, title = "Notes", done = FALSE)`: plain values (see the
  Values section) or new containers such as `loro_list("a", "b")`. These
  are [dynamic dots](https://rlang.r-lib.org/reference/dyn-dots.html),
  so a named list can be spliced in with `!!!` and a key held in a
  variable can be used with `"{key}" := value`. Values are stored in
  order, so if one is rejected the ones before it stay set. For
  `map_delete()`, the keys to remove, as strings or character vectors.

- map:

  A map handle, from
  [`doc_map()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container. A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  is also accepted and stands for its default root container; see
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md).

- key:

  A string.

- type:

  Type of the child container: `"text"`, `"map"`, `"list"`,
  `"movable_list"`, `"counter"`, or `"tree"`.

- keys:

  A character vector of keys.

## Value

`map_set()` returns `.map` invisibly, and `map_delete()` and
`map_clear()` return `map` invisibly. `map_ensure_container()` returns a
container handle, and `map_last_editor()` a string. `map_get()` returns
a value or handle, `map_has()` a logical vector, `map_keys()` a
character vector, and `map_length()` an integer.

## Values

Plain values are converted as follows. `NULL` and `NA` become null.
Length-one logical, numeric, and character vectors become scalars; other
unnamed vectors and unnamed lists become lists; named vectors and named
lists become maps. Raw vectors are stored as binary, and any names on
them are dropped. Objects with a class attribute (factors, dates, data
frames) are rejected, and other attributes such as `dim` are ignored.

Strings are stored as UTF-8. Strings in another encoding are converted,
and strings that are not valid text are rejected. Values may be nested
up to 1000 levels deep.

An empty vector or list is always stored as an empty list, even if it
carries a `names` attribute, so an empty map cannot be written as a
plain value.

A plain value is stored as a single unit: concurrent changes replace it
whole. To let replicas merge edits inside a value, store a child
container instead. Values read back as scalars and (possibly nested)
lists; map entries are returned sorted by key, comparing the keys byte
by byte (as `sort(method = "radix")` does), which is not always the
order [`sort()`](https://rdrr.io/r/base/sort.html) gives in your locale.

## Examples

``` r
doc = loro_doc()
meta = doc_map(doc, "meta")
map_set(meta, title = "Notes", tags = c("a", "b"))

meta$body = loro_text("Hello")

map_keys(meta)
#> [1] "body"  "tags"  "title"
map_get(meta, "title")
#> [1] "Notes"
meta$title
#> [1] "Notes"
text_get(meta$body)
#> [1] "Hello"

meta$title = "Shopping"
map_delete(meta, "tags")
as.list(meta)
#> $body
#> [1] "Hello"
#> 
#> $title
#> [1] "Shopping"
#> 
```
