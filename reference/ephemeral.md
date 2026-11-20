# Ephemeral state

An ephemeral store shares short-lived state between replicas, such as
who is present and where their cursors are. Unlike a document it keeps
no history: each key holds only its most recent value (the last write
wins), and entries expire when they stop being refreshed.

- `ephemeral_store()` creates a store.

- `ephemeral_set()` writes values given as `key = value` arguments,
  `ephemeral_get()` reads one key, and `ephemeral_delete()` removes the
  keys named in `...`. Setting a key again refreshes it.

- `ephemeral_keys()` and `ephemeral_values()` list the current entries.

- `ephemeral_encode()` serializes one key, or every key when `key` is
  `NULL`, and `ephemeral_apply()` merges such bytes into a store.

- `ephemeral_remove_outdated()` drops entries that have expired. Expired
  entries are already left out of `ephemeral_encode()`, but they are
  only removed, and reported to subscribers, when this is called.

- `ephemeral_subscribe()` calls `callback(event)` when entries change.
  An event is a list with `by` (`"local"`, `"import"`, or `"timeout"`)
  and character vectors `added`, `updated`, and `removed` naming the
  affected keys.

- `ephemeral_subscribe_local_updates()` calls `callback(bytes)` after
  each local change with an update to send to other stores.

Writes are ordered by a timestamp with millisecond resolution, and a
store ignores an incoming write that is not newer than the one it holds.
Two writes to one key within the same millisecond can therefore leave
other stores with the first value until the key is written again. This
is harmless for state that is refreshed continually, but do not rely on
an ephemeral store to deliver every intermediate value.

Keys are usually chosen per replica (for example the peer id) so that
replicas do not overwrite each other. Subscriptions behave as described
in
[`doc_subscribe()`](https://rundel.github.io/creditor/reference/subscribe.md)
and are stopped with
[`unsubscribe()`](https://rundel.github.io/creditor/reference/subscribe.md).

## Usage

``` r
ephemeral_store(timeout = 30)

ephemeral_set(store, ...)

ephemeral_get(store, key)

ephemeral_delete(store, ...)

ephemeral_keys(store)

ephemeral_values(store)

ephemeral_encode(store, key = NULL)

ephemeral_apply(store, bytes)

ephemeral_remove_outdated(store)

ephemeral_subscribe(store, callback)

ephemeral_subscribe_local_updates(store, callback)
```

## Arguments

- timeout:

  Seconds after which an entry that has not been updated expires.

- store:

  An ephemeral store.

- ...:

  Plain values to store, each named with its key; see
  [`map_set()`](https://rundel.github.io/creditor/reference/map.md). For
  `ephemeral_delete()`, the keys to remove, as strings or character
  vectors.

- key:

  A string.

- bytes:

  A raw vector from `ephemeral_encode()` or a local updates
  subscription.

- callback:

  A function of one argument.

## Value

`ephemeral_store()` returns a store. `ephemeral_get()` returns a value
or `NULL`, `ephemeral_keys()` a character vector, `ephemeral_values()` a
named list, and `ephemeral_encode()` a raw vector. The subscribe
functions return a subscription object. The others return `store`
invisibly.

## Examples

``` r
a = ephemeral_store()
b = ephemeral_store()
sync = ephemeral_subscribe_local_updates(a, function(bytes) {
  ephemeral_apply(b, bytes)
})

ephemeral_set(a, alice = list(name = "Alice", cursor = 12L))
ephemeral_values(b)
#> $alice
#> $alice$cursor
#> [1] 12
#> 
#> $alice$name
#> [1] "Alice"
#> 
#> 

unsubscribe(sync)
```
