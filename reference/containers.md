# Container handles

A document's data lives in containers. `doc_text()`, `doc_map()`,
`doc_list()`, `doc_movable_list()`, `doc_counter()`, and `doc_tree()`
return a handle to the root container with the given name, creating it
on first use. Handles to nested containers come from
[`map_set_container()`](https://rundel.github.io/creditor/reference/map.md),
[`list_insert_container()`](https://rundel.github.io/creditor/reference/list.md),
[`map_get()`](https://rundel.github.io/creditor/reference/map.md), and
[`list_get()`](https://rundel.github.io/creditor/reference/list.md).

A handle is a `loro_text`, `loro_map`, `loro_list`, `loro_movable_list`,
`loro_counter`, or `loro_tree` object. Like a
[`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md),
it has reference semantics: editing through a handle changes the
document it belongs to.

- `container_value()` returns the contents of a container: a string for
  text, a number for a counter, and a list for a map or list. A tree is
  a list of its root nodes, each a list with `id`, `parent` (`NA` at the
  top level), a 1-based `index`, a `fractional_index` (Loro's internal
  sort key), `meta`, and `children` (a list of nodes of the same form).
  Nested containers are expanded to their contents by default; with
  `deep = FALSE` they appear as container id strings.

- `container_is_deleted()` reports whether the container has been
  removed from its document, for example because its key was overwritten
  or its parent deleted. A handle to a deleted container can still be
  read, but editing through it is an error.

- `container_id()` returns the container's unique id as a string.

Root container names are shared across types within a document's value,
so use distinct names for different root containers: if two root
containers of different types have the same name, each keeps its own
contents but
[`doc_value()`](https://rundel.github.io/creditor/reference/doc.md)
shows only one of them.

Asking for a root container creates it. Once `doc_map(doc, "notes")` has
been called,
[`doc_value()`](https://rundel.github.io/creditor/reference/doc.md)
includes an empty `notes` entry, on this replica and on any that later
import from it, even if nothing is ever stored there. Two replicas with
the same edits can therefore differ in which empty root containers their
values list.

## Usage

``` r
doc_text(doc, name = "text")

doc_map(doc, name = "map")

doc_list(doc, name = "list")

doc_movable_list(doc, name = "list")

doc_counter(doc, name = "counter")

doc_tree(doc, name = "tree")

container_value(x, deep = TRUE)

container_is_deleted(x)

container_id(x)
```

## Arguments

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- name:

  Name of the root container.

- x:

  A container handle.

- deep:

  Whether to expand nested containers.

## Value

`doc_text()`, `doc_map()`, `doc_list()`, `doc_movable_list()`,
`doc_counter()`, and `doc_tree()` return container handles;
`container_value()` returns a string, number, or list; `container_id()`
returns a string; and `container_is_deleted()` returns a logical.

## Examples

``` r
doc = loro_doc()

text = doc_text(doc, "body")
text_insert(text, 1, "Hello")

meta = doc_map(doc, "meta")
map_set(meta, "title", "Greeting")

container_value(meta)
#> $title
#> [1] "Greeting"
#> 
container_id(text)
#> [1] "cid:root-body:Text"
doc_value(doc)
#> $body
#> [1] "Hello"
#> 
#> $meta
#> $meta$title
#> [1] "Greeting"
#> 
#> 
```
