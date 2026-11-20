# Edit maps

A map holds values under string keys. When replicas set the same key
concurrently, one write wins on every replica.

- `map_set()` stores a plain value under `key`.

- `map_set_container()` stores a new, empty child container under `key`
  and returns its handle.

- `map_get()` returns the value under `key`, a handle if it is a
  container, or `NULL` if the key is absent.

- `map_ensure_container()` returns the child container under `key`,
  creating it if the key is empty. Unlike `map_set_container()`, which
  always makes a fresh container, the container it creates is shared:
  replicas that each create it independently end up editing the same
  one, with all their edits merged. Use it for containers that are
  created lazily on first use. It is an error if `key` already holds a
  plain value, a container of another type, or a container made by
  `map_set_container()`.

- `map_delete()` removes `key`, and `map_clear()` removes every key.

- `map_last_editor()` returns the peer id of the replica that last wrote
  `key`, or `NA` if the key has never been written.

- `map_keys()` returns the keys in sorted order, and `map_length()` the
  number of entries.

## Usage

``` r
map_set(map, key, value)

map_set_container(map, key, type)

map_get(map, key)

map_delete(map, key)

map_keys(map)

map_length(map)

map_ensure_container(map, key, type)

map_clear(map)

map_last_editor(map, key)
```

## Arguments

- map:

  A map handle, from
  [`doc_map()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container.

- key:

  A string.

- value:

  A plain value; see the Values section.

- type:

  Type of the child container: `"text"`, `"map"`, `"list"`,
  `"movable_list"`, `"counter"`, or `"tree"`.

## Value

`map_set()`, `map_delete()`, and `map_clear()` return `map` invisibly.
`map_set_container()` and `map_ensure_container()` return a container
handle, and `map_last_editor()` a string. `map_get()` returns a value or
handle, `map_keys()` a character vector, and `map_length()` an integer.

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
map_set(meta, "title", "Notes")
map_set(meta, "tags", c("a", "b"))

body = map_set_container(meta, "body", "text")
text_insert(body, 1, "Hello")

map_keys(meta)
#> [1] "body"  "tags"  "title"
map_get(meta, "title")
#> [1] "Notes"
text_get(map_get(meta, "body"))
#> [1] "Hello"
container_value(meta)
#> $body
#> [1] "Hello"
#> 
#> $tags
#> $tags[[1]]
#> [1] "a"
#> 
#> $tags[[2]]
#> [1] "b"
#> 
#> 
#> $title
#> [1] "Notes"
#> 
```
