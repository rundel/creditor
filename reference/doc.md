# Document identity, replicas, and contents

- `doc_peer_id()` returns the peer id of this replica as a string, and
  `doc_set_peer_id()` changes it. Two replicas must never edit under the
  same peer id.

- `doc_fork()` returns an independent replica with the same history and
  a new peer id. With `at`, the replica holds the document as it was at
  that version.

- `doc_commit()` commits pending edits as one change, optionally labeled
  with a `message` that is kept in the history and shown by
  [`doc_changes()`](https://rundel.github.io/creditor/reference/history.md).
  An `origin` is a label for this commit that is not stored or
  synchronized: it is passed to subscribers on this replica as
  `event$origin`, so they can tell where a change came from, and an undo
  manager can be told to ignore commits by origin. A `timestamp` is
  stored with the change in place of the current time, whether or not
  [`doc_record_timestamps()`](https://rundel.github.io/creditor/reference/history.md)
  is on; Loro keeps timestamps non-decreasing, so one earlier than the
  latest existing timestamp is replaced by that latest one. Edits are
  also committed implicitly on export, import, and checkout.

- `doc_value()` returns the whole document as a named list with one
  element per root container. It is an error if containers are nested
  more than 1000 levels deep.

- `doc_get_path()` returns the value at a slash-separated path such as
  `"note/items/1"`: a root container name, then map keys, 0-based list
  positions, or tree node ids. Containers are returned as handles, and
  `NULL` means nothing is there. The path syntax cannot express every
  key: a map key that contains `/`, or that looks like a number, is not
  reachable this way. Use `doc_jsonpath()` with a quoted key, such as
  `"$.m['a/b']"`, for those.

- `doc_jsonpath()` returns a list of everything matching a JSONPath
  expression such as `"$.note.items[*]"`. Loro does not support every
  JSONPath feature: a query that has to descend into a tree container,
  or that uses the [`match()`](https://rdrr.io/r/base/match.html) or
  [`search()`](https://rdrr.io/r/base/search.html) functions, is an
  error.

## Usage

``` r
doc_peer_id(doc)

doc_set_peer_id(doc, peer_id)

doc_fork(doc, at = NULL)

doc_commit(doc, message = NULL, origin = NULL, timestamp = NULL)

doc_value(doc)

doc_get_path(doc, path)

doc_jsonpath(doc, path)
```

## Arguments

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- peer_id:

  A peer id: a whole number or a string of digits.

- at:

  A version from
  [`doc_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
  to fork at, or `NULL` for the current version.

- message:

  A string describing the change, or `NULL`.

- origin:

  A string labeling the source of the commit, or `NULL`.

- timestamp:

  The time to record for the commit, as a `POSIXct` or a number of
  seconds since 1970, or `NULL`.

- path:

  A path or JSONPath expression, as a string.

## Value

`doc_set_peer_id()` returns `doc` invisibly. `doc_peer_id()` returns a
string, `doc_fork()` a new `loro_doc`, `doc_commit()` returns `doc`
invisibly, and `doc_value()` a named list. `doc_get_path()` returns a
value or container handle, and `doc_jsonpath()` a list of them.

## Examples

``` r
doc = loro_doc(peer_id = 1)
text_insert(doc_text(doc), 1, "Hello")
doc_peer_id(doc)
#> [1] "1"
doc_value(doc)
#> $text
#> [1] "Hello"
#> 
```
