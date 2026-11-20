# Synchronize documents

Replicas exchange state as raw vectors, which can be written to disk or
sent over any transport.

- `doc_export()` serializes a whole document as a snapshot: its contents
  and full history.

- `doc_export_updates()` serializes only the changes made since the
  version `from`, or the complete history when `from` is `NULL`.

- `doc_export_shallow()` serializes a shallow snapshot: the contents
  plus only the history after the version `since`. Dropping old history
  can make the export much smaller for a document with a long history,
  but a document loaded from it cannot check out versions before `since`
  or merge edits that branch off before it.

- `doc_import()` merges a snapshot or updates into a document. Importing
  is commutative and idempotent, so replicas that have seen the same
  updates hold the same contents. `bytes` may also be a list of raw
  vectors, which are imported together in one step.

- `doc_version()` returns the document's current version vector, for use
  as the `from` argument of `doc_export_updates()`. See
  [`as_version()`](https://rundel.github.io/creditor/reference/versions.md).

- `doc_is_shallow()` reports whether a document lacks its early history
  because it was loaded from a shallow snapshot.

- `blob_metadata()` describes an exported raw vector without importing
  it.

- `doc_export_json()` and `doc_import_json()` exchange changes as JSON
  text. This is larger than the binary format but readable, and useful
  for inspection and debugging. JSON cannot carry values nested more
  than about 120 levels deep: such a document exports, but the result
  cannot be imported again. It also cannot carry containers created with
  [`map_ensure_container()`](https://rundel.github.io/creditor/reference/map.md),
  and `doc_export_json()` refuses to export changes that create one.

## Usage

``` r
doc_export(doc)

doc_export_updates(doc, from = NULL)

doc_export_shallow(doc, since = NULL)

doc_import(doc, bytes)

doc_import_status(doc)

doc_version(doc)

doc_is_shallow(doc)

blob_metadata(bytes)

doc_export_json(doc, from = NULL, to = NULL)

doc_import_json(doc, json)
```

## Arguments

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- from:

  A version returned by `doc_version()` to start from, typically that of
  the replica the updates are destined for, or `NULL` for the beginning.

- since:

  A version: frontiers from
  [`doc_frontiers()`](https://rundel.github.io/creditor/reference/history.md),
  or the version after one change, named by its number in
  [`doc_changes()`](https://rundel.github.io/creditor/reference/history.md)
  order or by its commit message. The default, the latest version, keeps
  no earlier history at all.

- bytes:

  A raw vector produced by one of the export functions, or for
  `doc_import()` a list of them.

- to:

  A version returned by `doc_version()` to stop at, or `NULL` for the
  latest.

- json:

  A string produced by `doc_export_json()`.

## Value

`doc_export()`, `doc_export_updates()`, and `doc_export_shallow()`
return a raw vector and `doc_version()` a version vector. `doc_import()`
and `doc_import_json()` return `doc` invisibly, and
`doc_import_status()` returns an import status or `NULL`; see the Import
status section. `doc_is_shallow()` returns a logical,
`doc_export_json()` a string, and `blob_metadata()` a list with `mode`,
`changes` (the number of changes), `start_timestamp` and
`end_timestamp`, and the versions `start_frontiers`, `start_version`,
and `end_version`.

## Import status

`doc_import()` and `doc_import_json()` return the document invisibly, so
they can be used in a pipe. The outcome of the most recent import into a
document is kept with it, and `doc_import_status()` returns it, or
`NULL` if nothing has been imported. Like the document, it is shared by
every reference to it, so it can be read from the original variable as
well as from the result of a pipe. It is a list of two tibbles,
`success` and `pending`, each with columns `peer`, `start`, and `end`
giving a range of that peer's operation counters. `success` holds the
operations that were applied. `pending` holds operations that arrived
before the changes they depend on; they are kept and applied
automatically once the missing changes are imported. A non-empty
`pending` means an earlier update was lost or is still in transit.

## Examples

``` r
a = loro_doc()
text_insert(a, 1, "Hello")

b = loro_doc()
doc_import(b, doc_export(a))

text_insert(a, 6, " world")
text_insert(b, 1, ">> ")

doc_import(b, doc_export_updates(a, from = doc_version(b)))
doc_import(a, doc_export_updates(b, from = doc_version(a)))
text_get(a)
#> [1] ">> Hello world"
text_get(b)
#> [1] ">> Hello world"
doc_import_status(b)
#> $success
#> # A tibble: 1 × 3
#>   peer                start   end
#>   <chr>               <int> <int>
#> 1 5467147587943920954     5    11
#> 
#> $pending
#> # A tibble: 0 × 3
#> # ℹ 3 variables: peer <chr>, start <int>, end <int>
#> 

# Imports return the document, so they can be piped
loro_doc() |> doc_import(doc_export(a)) |> text_get()
#> [1] ">> Hello world"

small = doc_export_shallow(a)
blob_metadata(small)$mode
#> [1] "shallow-snapshot"
```
