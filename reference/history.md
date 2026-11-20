# Document history

A document keeps its full editing history, so earlier versions can be
inspected, compared, and restored.

- `doc_frontiers()` returns the version the document is currently
  showing. Unlike the version vector from
  [`doc_version()`](https://rundel.github.io/creditor/reference/doc_sync.md),
  which is meant for synchronization, frontiers are a compact name for
  one point in history.

- `doc_frontiers_to_version()` and `doc_version_to_frontiers()` convert
  between the two kinds of version. For example, converting a row of
  `doc_changes()` to a version vector lets
  [`doc_export_updates()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  produce the updates made since that change.

- `doc_compare_frontiers()` orders two versions: `-1` if `x` is an
  ancestor of `y`, `1` if it is a descendant, `0` if they are the same,
  and `NA` if they are concurrent (neither contains the other).

- `doc_changes()` returns one row per change in the history, and
  `doc_change()` the one change containing a given operation.

- `doc_change_count()` and `doc_op_count()` return the number of changes
  and of individual operations in the history.

- `doc_changed_containers()` returns the ids of the containers modified
  by the given changes.

- `doc_checkout()` moves the document to an earlier version, or back to
  the latest when `frontiers` is `NULL`. While checked out at an earlier
  version the document is detached: it is read-only, and imported
  updates are stored but not shown until it returns to the latest
  version. `doc_is_detached()` reports this state.

- `doc_detach()` detaches the document at its current version, freezing
  what it shows while imports continue to be stored.

- `doc_set_detached_editing()` allows a detached document to be edited,
  which starts a new branch of history from the checked-out version;
  `doc_is_detached_editing()` reports the setting. See the Detached
  editing section.

- `doc_revert_to()` adds new changes that restore the contents of an
  earlier version and commits them. History is kept, and the revert
  synchronizes to other replicas like any other edit.

- `doc_diff()` returns the differences between two versions.

- `doc_apply_diff()` takes the changes that `source` made between two of
  its versions and applies them to `doc` as new, committed edits. With
  `source` left as `doc` this replays or (with the versions swapped)
  undoes a span of its own history; with another document it copies a
  span of work across without merging the two histories. The changes are
  applied by position, so `doc` must hold contents that match what
  `source` held at `from`; otherwise the call fails or lands edits in
  the wrong place.

- `doc_record_timestamps()` turns on recording of the wall-clock time of
  each new change. It is off by default.

## Usage

``` r
doc_frontiers(doc)

doc_changes(doc)

doc_change(doc, peer, counter)

doc_change_count(doc)

doc_op_count(doc)

doc_changed_containers(doc, changes)

doc_frontiers_to_version(doc, frontiers)

doc_version_to_frontiers(doc, version)

doc_compare_frontiers(doc, x, y)

doc_checkout(doc, frontiers = NULL)

doc_is_detached(doc)

doc_detach(doc)

doc_set_detached_editing(doc, enable = TRUE)

doc_is_detached_editing(doc)

doc_revert_to(doc, frontiers)

doc_diff(doc, from, to)

doc_apply_diff(doc, from, to, source = doc)

doc_record_timestamps(doc, record = TRUE)
```

## Arguments

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- peer, counter:

  The id of an operation: a peer id string and an operation counter.

- changes:

  A data frame of changes, such as rows of `doc_changes()`.

- frontiers, from, to, x, y:

  A version: frontiers from `doc_frontiers()` (see
  [`as_frontiers()`](https://rundel.github.io/creditor/reference/versions.md)),
  or the version after one change, named by its number in
  `doc_changes()` order or by its commit message. For
  `doc_apply_diff()`, change numbers and messages refer to `source`.

- version:

  A version vector from
  [`doc_version()`](https://rundel.github.io/creditor/reference/doc_sync.md).

- enable:

  Whether to allow editing while detached.

- source:

  The
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  whose history `from` and `to` refer to.

- record:

  Whether to record timestamps.

## Value

`doc_detach()` and `doc_set_detached_editing()` return `doc` invisibly,
and `doc_is_detached_editing()` a logical. `doc_frontiers()`,
`doc_frontiers_to_version()`, and `doc_version_to_frontiers()` return
raw vectors. `doc_compare_frontiers()` returns an integer,
`doc_change_count()` and `doc_op_count()` integers, and
`doc_changed_containers()` a character vector. `doc_changes()` and
`doc_change()` return a tibble, `doc_is_detached()` a logical, and
`doc_diff()` a named list. `doc_checkout()`, `doc_revert_to()`,
`doc_apply_diff()`, and `doc_record_timestamps()` return `doc`
invisibly.

## Detached editing

With detached editing enabled, edits made while checked out at an
earlier version are recorded as changes that follow that version,
concurrent with everything that came after it. Returning to the latest
version with `doc_checkout(doc)` merges the branch with the rest of the
history, as if another replica had made those edits.

To keep the branches distinct, the document takes a new random peer id
at each checkout while this is enabled, and keeps the last one after
returning to the latest version, so do not rely on
[`doc_peer_id()`](https://rundel.github.io/creditor/reference/doc.md)
staying fixed. The setting belongs to this `loro_doc` object and is not
saved in exports.

## Changes

`doc_changes()` returns a tibble, in causal order, with columns:

- `peer`, `counter`: the id of the change's first operation.

- `lamport`: its logical timestamp.

- `length`: the number of operations in the change.

- `timestamp`: when it was committed (`NA` if not recorded).

- `message`: the commit message (`NA` if none).

- `frontiers`: a list column holding the version just after the change,
  suitable for `doc_checkout()`, `doc_revert_to()`, `doc_diff()`, and
  [`doc_fork()`](https://rundel.github.io/creditor/reference/doc.md).

Consecutive commits by one peer that carry the same message, or no
message, may be stored as a single change, so rows do not correspond
one-to-one with calls to
[`doc_commit()`](https://rundel.github.io/creditor/reference/doc.md). An
empty message is the same as no message, and a commit with nothing to
commit is dropped along with its message.

## Diffs

`doc_diff()` returns a named list with one element per changed
container, named by container id (see
[`container_id()`](https://rundel.github.io/creditor/reference/containers.md)).
Each element has a `type` and:

- for text, `delta`: delta ops as in
  [`text_apply_delta()`](https://rundel.github.io/creditor/reference/richtext.md);

- for a list or movable list (both have type `"list"`), `delta`: ops
  with `retain` or `delete` counts, or `insert` holding a list of new
  elements;

- for a map, `updated`: a named list of the new values of keys that were
  set, and `deleted`: a character vector of keys that were removed;

- for a counter, `increment`: the net amount added;

- for a tree, `diff`: a list of node changes, each with `node`, an
  `action` (`"create"`, `"move"`, or `"delete"`), and the `parent` and
  1-based `index` it now has and, for moves and deletes, the
  `old_parent` and `old_index` it had (`NA` parents are the top level).

Child containers appear by their contents.

## Examples

``` r
doc = loro_doc()
text = doc_text(doc)

text_insert(text, 1, "Hello")
doc_commit(doc, "greeting")
v1 = doc_frontiers(doc)

text_insert(text, 6, " world")
doc_commit(doc, "audience")
v2 = doc_frontiers(doc)

doc_changes(doc)[, c("lamport", "length", "message")]
#> # A tibble: 2 × 3
#>   lamport length message 
#>     <int>  <int> <chr>   
#> 1       0      5 greeting
#> 2       5      6 audience
str(doc_diff(doc, v1, v2))
#> List of 1
#>  $ cid:root-text:Text:List of 2
#>   ..$ type : chr "text"
#>   ..$ delta:List of 2
#>   .. ..$ :List of 1
#>   .. .. ..$ retain: int 5
#>   .. ..$ :List of 1
#>   .. .. ..$ insert: chr " world"

doc_checkout(doc, v1)
text_get(text)
#> [1] "Hello"
doc_checkout(doc)

doc_revert_to(doc, v1)
text_get(text)
#> [1] "Hello"
```
