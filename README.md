# creditor

<!-- badges: start -->
[![R-CMD-check](https://github.com/rundel/creditor/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/rundel/creditor/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

Exploratory R bindings to [Loro](https://loro.dev), a Rust library of conflict-free replicated data types (CRDTs). Replicas of a document edit independently, exchange updates as raw vectors, and converge to the same contents. Text (including rich text marks and cursors), map, list, movable list, counter, and tree containers are supported, and they can be nested. Documents keep their full history, which can be listed, compared, checked out, and reverted. Exports can be full or shallow snapshots, incremental updates, or JSON. Subscriptions report changes as they are committed, an undo manager reverses local edits, and an ephemeral store shares presence state such as cursors.

See `vignette("containers", package = "creditor")` for a tour of each container type and how it merges concurrent edits.

## Installation

Building from source needs a Rust toolchain (cargo and rustc >= 1.85).

```r
# install.packages("pak")
pak::pak("rundel/creditor")
```

## Example

Two replicas edit the same text concurrently and then merge.

```r
library(creditor)

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
```

Containers nest: a map or list can hold plain values or child containers, each of which merges independently.

```r
doc = loro_doc()
note = doc_map(doc, "note")
map_set(note, title = "Groceries")

items = map_set_container(note, "items", "list")
list_push(items, "milk", "eggs")

body = map_set_container(note, "body", "text")
text_insert(body, 1, "Buy before Friday")

str(doc_value(doc))
#> List of 1
#>  $ note:List of 3
#>   ..$ body : chr "Buy before Friday"
#>   ..$ items:List of 2
#>   .. ..$ : chr "milk"
#>   .. ..$ : chr "eggs"
#>   ..$ title: chr "Groceries"
```

Text can carry marks, and a cursor keeps pointing at the same character as the text changes.

```r
doc = loro_doc()
text = doc_text(doc)
text_insert(text, 1, "Hello world")
text_mark(text, 1, 5, bold = TRUE)
cursor = text_cursor(text, 7)

text_update(text, "Hello brave new world")
str(text_delta(text))
#> List of 2
#>  $ :List of 2
#>   ..$ insert    : chr "Hello"
#>   ..$ attributes:List of 1
#>   .. ..$ bold: logi TRUE
#>  $ :List of 1
#>   ..$ insert: chr " brave new world"
cursor_pos(doc, cursor)
#> [1] 17
```

Every version stays reachable.

```r
doc = loro_doc()
text = doc_text(doc)
text_insert(text, 1, "Hello")
doc_commit(doc, "greeting")
text_insert(text, 6, " world")
doc_commit(doc, "audience")

changes = doc_changes(doc)
changes[, c("lamport", "length", "message")]
#>   lamport length  message
#> 1       0      5 greeting
#> 2       5      6 audience

doc_checkout(doc, changes$frontiers[[1]])
text_get(text)
#> [1] "Hello"
doc_checkout(doc)
text_get(text)
#> [1] "Hello world"
```

Subscriptions make live sync a one-liner, and undo reverses only local edits.

```r
a = loro_doc()
b = loro_doc()
sync = doc_subscribe_local_updates(a, function(bytes) doc_import(b, bytes))
manager = doc_undo_manager(a)

text_insert(a, 1, "Hello")
doc_commit(a)
text_get(b)
#> [1] "Hello"

undo(manager)
#> [1] TRUE
text_get(b)
#> [1] ""

unsubscribe(sync)
```

## Shiny example

An example app shows two replicas of one document side by side. Each pane can be taken offline to make concurrent edits, which merge when it comes back online, and a history slider below the panes scrubs through the merged document's versions with each step's insertions and deletions highlighted.

```r
shiny::runApp(system.file("examples/sync-editors", package = "creditor"))
```
