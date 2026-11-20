

<!-- README.md is generated from README.qmd. Please edit that file. -->

# creditor

<!-- badges: start -->
[![R-CMD-check](https://github.com/rundel/creditor/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/rundel/creditor/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

Exploratory R bindings to [Loro](https://loro.dev), a Rust library of conflict-free replicated data types (CRDTs). Replicas of a document edit independently, exchange updates as raw vectors, and converge to the same contents. Text (including rich text marks and cursors), map, list, movable list, counter, and tree containers are supported, and they can be nested. Documents keep their full history, which can be listed, compared, checked out, and reverted. Exports can be full or shallow snapshots, incremental updates, or JSON. Subscriptions report changes as they are committed, an undo manager reverses local edits, and an ephemeral store shares presence state such as cursors.

See `vignette("containers", package = "creditor")` for a tour of each container type and how it merges concurrent edits.

## Installation

Building from source needs a Rust toolchain: cargo and `rustc >= 1.85`.

``` r
# install.packages("pak")
pak::pak("rundel/creditor")
```

## Example

Editing functions return the document or container they were given, so edits chain with the pipe.

Two replicas edit the same text concurrently and then merge.

``` r
library(creditor)

# Replica `a` starts the document with some text, and replica `b` starts from a snapshot of `a`
a = loro_doc() |>
  text_insert(1, "Hello")
b = loro_doc() |>
  doc_import(doc_export(a))

# Both replicas edit the text independently, without syncing
text_push(a, " world")
text_insert(b, 1, ">> ")

# Each replica sends the other the updates it is missing, and both edits are kept
b |>
  doc_import(doc_export_updates(a, from = doc_version(b))) |>
  text_get()
```

    [1] ">> Hello world"

``` r
a |>
  doc_import(doc_export_updates(b, from = doc_version(a))) |>
  text_get()
```

    [1] ">> Hello world"

Containers nest: a map or list can hold plain values or child containers, each of which merges independently. New containers are made with `loro_text()`, `loro_list()`, `loro_map()`, and friends, and stored like any other value.

``` r
doc = loro_doc()

# A plain value (the title) is replaced whole when edited concurrently, while child containers
# (the list and the text) merge concurrent edits to their contents
note = doc_map(doc, "note") |>
  map_set(
    title = "Groceries",
    items = loro_list("milk", "eggs"),
    body = loro_text("Buy before Friday")
  )

# Edit a child container in place
note$items |>
  list_push("bread")

doc |>
  doc_value() |>
  str()
```

    List of 1
     $ note:List of 3
      ..$ body : chr "Buy before Friday"
      ..$ items:List of 3
      .. ..$ : chr "milk"
      .. ..$ : chr "eggs"
      .. ..$ : chr "bread"
      ..$ title: chr "Groceries"

Text can carry marks, and a cursor keeps pointing at the same character as the text changes.

``` r
# Mark characters 1 to 5 ("Hello") as bold
doc = loro_doc() |>
  text_insert(1, "Hello world") |>
  text_mark(1, 5, bold = TRUE)

# A cursor at the "w" of "world" (character 7)
cursor = text_cursor(doc, 7)

# Rewrite the text; only the differences are applied, so the mark and cursor survive. The delta
# shows the text as runs of characters with their marks
doc |>
  text_update("Hello brave new world") |>
  text_delta() |>
  str()
```

    List of 2
     $ :List of 2
      ..$ insert    : chr "Hello"
      ..$ attributes:List of 1
      .. ..$ bold: logi TRUE
     $ :List of 1
      ..$ insert: chr " brave new world"

``` r
# The cursor has moved with the "w", which is now character 17
cursor_pos(doc, cursor)
```

    [1] 17

Every version stays reachable.

``` r
# Two commits, each labeled with a message
doc = loro_doc(peer_id = 1) |>
  text_insert(1, "Hello") |>
  doc_commit("greeting") |>
  text_push(" world") |>
  doc_commit("audience")

# One row per change
(changes = doc_changes(doc))
```

    # A tibble: 2 × 7
      peer  counter lamport length timestamp message  frontiers
      <chr>   <int>   <int>  <int> <dttm>    <chr>    <list>   
    1 1           0       0      5 NA        greeting <4@1>    
    2 1           5       5      6 NA        audience <10@1>   

``` r
# Read the document as it was after the greeting commit, from a copy at that version
doc |>
  doc_fork(at = "greeting") |>
  text_get()
```

    [1] "Hello"

Subscriptions make live sync a one-liner, and undo reverses only local edits.

``` r
a = loro_doc()
b = loro_doc()

# Send every update committed on `a` straight to `b`
sync = doc_subscribe_local_updates(a, \(bytes) doc_import(b, bytes))

# Track `a`'s local edits so they can be undone
manager = doc_undo_manager(a)

# Committing on `a` delivers the update to `b`
a |>
  text_insert(1, "Hello") |>
  doc_commit()
text_get(b)
```

    [1] "Hello"

``` r
# Undo is itself an edit, so it syncs to `b` too
undo(manager)
text_get(b)
```

    [1] ""

``` r
# Stop syncing
unsubscribe(sync)
```

## Shiny example

An example app shows two replicas of one document side by side. Each pane can be taken offline to make concurrent edits, which merge when it comes back online. Below the panes a timeline shows every edit as a bubble, in one row per replica above an axis of edit times; hovering a bubble shows what was changed and by whom, and selecting one shows the text at that point with the edit's insertions and deletions highlighted.

``` r
shiny::runApp(system.file("examples/sync-editors", package = "creditor"))
```
