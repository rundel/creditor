# Subscribe to changes

Subscriptions call an R function when a document changes.

- `doc_subscribe()` calls `callback(event)` for every committed change,
  whether made locally, imported from another replica, or caused by a
  checkout. With `container`, only changes to that container and the
  containers nested inside it are reported.

- `doc_subscribe_local_updates()` calls `callback(bytes)` after each
  local commit with the update it produced: a raw vector that another
  replica can pass to
  [`doc_import()`](https://rundel.github.io/creditor/reference/doc_sync.md).
  This is the building block for live synchronization.

- `doc_subscribe_first_commit()` calls `callback(peer)` the first time
  this document commits a local change under a given peer id, which is a
  natural moment to record who that peer is (for example in a map of
  authors). It fires again if the document's peer id changes, but not
  for peers whose changes are imported.

- `doc_subscribe_peer_id()` calls `callback(peer)` with the new peer id
  whenever this document's own peer id changes.

- `unsubscribe()` stops a subscription.

## Usage

``` r
doc_subscribe(doc, callback, container = NULL)

doc_subscribe_local_updates(doc, callback)

doc_subscribe_first_commit(doc, callback)

doc_subscribe_peer_id(doc, callback)

unsubscribe(subscription)
```

## Arguments

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- callback:

  A function of one argument.

- container:

  A container handle to limit the subscription to, or `NULL` for the
  whole document.

- subscription:

  An object returned by one of the subscribe functions.

## Value

The subscribe functions return a subscription object. `unsubscribe()`
returns `NULL` invisibly.

## Events

An `event` is a list with:

- `by`: what caused the change: `"local"`, `"import"`, or `"checkout"`.

- `origin`: the origin label of the commit, usually `""`.

- `diff`: the changes, in the format returned by
  [`doc_diff()`](https://rundel.github.io/creditor/reference/history.md).

## Timing

Changes are reported when they are committed, not when each edit is
made, so call
[`doc_commit()`](https://rundel.github.io/creditor/reference/doc.md) to
flush pending edits. Callbacks run after the creditor function that
committed or imported the change has finished its work, just before it
returns, so a callback can safely read or edit the document. Events are
delivered in the order they occurred: if a callback itself commits a
change, the resulting event is delivered after the callbacks for the
current event have run. An error in a callback is reported as a warning
and does not interrupt the function that triggered it.

A subscription stays active until `unsubscribe()` is called, even if the
object returned here is discarded and even after its document is no
longer referenced, so unsubscribe when you are done. A document that is
dropped with uncommitted edits commits them as it is freed, which can
deliver one last event to a subscription left on it.

## Examples

``` r
a = loro_doc()
b = loro_doc()

sync = doc_subscribe_local_updates(a, function(bytes) doc_import(b, bytes))
watch = doc_subscribe(b, function(event) {
  cat("b changed by", event$by, "\n")
})

text_insert(a, 1, "Hello")
doc_commit(a)
#> b changed by import 
text_get(b)
#> [1] "Hello"

unsubscribe(sync)
unsubscribe(watch)
```
