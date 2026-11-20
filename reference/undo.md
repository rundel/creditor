# Undo and redo

An undo manager tracks the local changes made to a document after it is
created, and can undo and redo them. Changes imported from other
replicas are never undone: an undo reverses only this replica's own
edits, adjusted for whatever others have done since.

- `doc_undo_manager()` creates an undo manager for `doc`.

- `undo()` and `redo()` step backward and forward. They return `TRUE` if
  the document changed.

- `can_undo()` and `can_redo()` report whether a step is available.

- `undo_count()` and `redo_count()` return the number of steps
  available.

- `undo_group()` evaluates `code` and records all the changes it makes
  as a single undo step. Pending edits are committed when the group
  starts and when it ends, so the step contains exactly the edits made
  by `code`. Groups cannot be nested. If changes to the same container
  are imported from another replica while the group is open, Loro closes
  the step early and the group is recorded as more than one step.

- `undo_pause()` stops recording local edits as undo steps until
  `undo_resume()`; `undo_is_paused()` reports the state. Edits made
  while paused cannot be undone.

- `undo_clear()` discards all undo and redo steps.

Checking out another version with
[`doc_checkout()`](https://rundel.github.io/creditor/reference/history.md)
clears the undo and redo history.

Undoing the deletion of a child container brings back its contents in a
new container with a new id. Handles to the old container remain deleted
(see
[`container_is_deleted()`](https://rundel.github.io/creditor/reference/containers.md)),
so fetch the container again from its parent after an undo.

Each commit is one undo step, so call
[`doc_commit()`](https://rundel.github.io/creditor/reference/doc.md)
between edits that should be undone separately. Commits closer together
than `merge_interval` are combined into one step.

## Usage

``` r
doc_undo_manager(
  doc,
  merge_interval = 0,
  max_steps = 100,
  exclude_origins = character()
)

undo_count(manager)

redo_count(manager)

undo_pause(manager)

undo_resume(manager)

undo_is_paused(manager)

undo_clear(manager)

undo(manager)

redo(manager)

can_undo(manager)

can_redo(manager)

undo_group(manager, code)
```

## Arguments

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- merge_interval:

  Commits made within this many milliseconds of the previous one join
  its undo step. The default, `0`, keeps every commit separate.

- max_steps:

  Maximum number of undo steps to keep.

- exclude_origins:

  A character vector of origin prefixes. Commits whose `origin` (see
  [`doc_commit()`](https://rundel.github.io/creditor/reference/doc.md))
  starts with one of them are not recorded as undo steps.

- manager:

  An undo manager from `doc_undo_manager()`.

- code:

  Code that edits the document.

## Value

`doc_undo_manager()` returns an undo manager. `undo()`, `redo()`,
`can_undo()`, `can_redo()`, and `undo_is_paused()` return a logical, and
`undo_count()` and `redo_count()` an integer. `undo_pause()`,
`undo_resume()`, and `undo_clear()` return `manager` invisibly.
`undo_group()` returns the value of `code`.

## Examples

``` r
doc = loro_doc()
text = doc_text(doc)
manager = doc_undo_manager(doc)

text_insert(text, 1, "Hello")
doc_commit(doc)
text_insert(text, 6, " world")
doc_commit(doc)

undo(manager)
#> [1] TRUE
text_get(text)
#> [1] "Hello"
redo(manager)
#> [1] TRUE
text_get(text)
#> [1] "Hello world"
```
