#' Ephemeral state
#'
#' @description
#' An ephemeral store shares short-lived state between replicas, such as
#' who is present and where their cursors are. Unlike a document it keeps
#' no history: each key holds only its most recent value (the last write
#' wins), and entries expire when they stop being refreshed.
#'
#' * `ephemeral_store()` creates a store.
#' * `ephemeral_set()`, `ephemeral_get()`, and `ephemeral_delete()` write,
#'   read, and remove one key. Setting a key again refreshes it.
#' * `ephemeral_keys()` and `ephemeral_values()` list the current
#'   entries.
#' * `ephemeral_encode()` serializes one key, or every key when `key` is
#'   `NULL`, and `ephemeral_apply()` merges such bytes into a store.
#' * `ephemeral_remove_outdated()` drops entries that have expired.
#'   Expired entries are already left out of `ephemeral_encode()`, but
#'   they are only removed, and reported to subscribers, when this is
#'   called.
#' * `ephemeral_subscribe()` calls `callback(event)` when entries
#'   change. An event is a list with `by` (`"local"`, `"import"`, or
#'   `"timeout"`) and character vectors `added`, `updated`, and
#'   `removed` naming the affected keys.
#' * `ephemeral_subscribe_local_updates()` calls `callback(bytes)` after
#'   each local change with an update to send to other stores.
#'
#' Writes are ordered by a timestamp with millisecond resolution, and a
#' store ignores an incoming write that is not newer than the one it
#' holds. Two writes to one key within the same millisecond can
#' therefore leave other stores with the first value until the key is
#' written again. This is harmless for state that is refreshed
#' continually, but do not rely on an ephemeral store to deliver every
#' intermediate value.
#'
#' Keys are usually chosen per replica (for example the peer id) so that
#' replicas do not overwrite each other. Subscriptions behave as
#' described in [`doc_subscribe()`] and are stopped with
#' [`unsubscribe()`].
#'
#' @param timeout Milliseconds after which an entry that has not been
#'   updated expires.
#' @param store An ephemeral store.
#' @param key A string.
#' @param value A plain value; see the Values section of [`map_set()`].
#' @param bytes A raw vector from `ephemeral_encode()` or a local
#'   updates subscription.
#' @param callback A function of one argument.
#'
#' @return `ephemeral_store()` returns a store. `ephemeral_get()` returns
#'   a value or `NULL`, `ephemeral_keys()` a character vector,
#'   `ephemeral_values()` a named list, and `ephemeral_encode()` a raw
#'   vector. The subscribe functions return a subscription object. The
#'   others return `store` invisibly.
#'
#' @examples
#' a = ephemeral_store()
#' b = ephemeral_store()
#' sync = ephemeral_subscribe_local_updates(a, function(bytes) {
#'   ephemeral_apply(b, bytes)
#' })
#'
#' ephemeral_set(a, "alice", list(name = "Alice", cursor = 12L))
#' ephemeral_values(b)
#'
#' unsubscribe(sync)
#'
#' @name ephemeral
NULL

loro_ephemeral_store = S7::new_class(
  "loro_ephemeral_store",
  package = "creditor",
  properties = list(ptr = S7::class_any)
)

check_store = function(store, call = sys.call(-1)) {
  if (!S7::S7_inherits(store, loro_ephemeral_store)) {
    cli::cli_abort(
      "{.arg store} must be a {.cls loro_ephemeral_store}, not {.obj_type_friendly {store}}.",
      call = call
    )
  }
  invisible(store)
}

#' @rdname ephemeral
#' @export
ephemeral_store = function(timeout = 30000) {
  timeout = check_count(timeout, "timeout", 1)
  loro_ephemeral_store(ptr = loro_ephemeral_new_impl(as.numeric(timeout)))
}

#' @rdname ephemeral
#' @export
ephemeral_set = function(store, key, value) {
  check_store(store)
  loro_ephemeral_set_impl(store@ptr, check_string(key, "key"), value)
  deliver_events()
  invisible(store)
}

#' @rdname ephemeral
#' @export
ephemeral_get = function(store, key) {
  check_store(store)
  loro_ephemeral_get_impl(store@ptr, check_string(key, "key"))
}

#' @rdname ephemeral
#' @export
ephemeral_delete = function(store, key) {
  check_store(store)
  loro_ephemeral_delete_impl(store@ptr, check_string(key, "key"))
  deliver_events()
  invisible(store)
}

#' @rdname ephemeral
#' @export
ephemeral_keys = function(store) {
  check_store(store)
  loro_ephemeral_keys_impl(store@ptr)
}

#' @rdname ephemeral
#' @export
ephemeral_values = function(store) {
  check_store(store)
  loro_ephemeral_values_impl(store@ptr)
}

#' @rdname ephemeral
#' @export
ephemeral_encode = function(store, key = NULL) {
  check_store(store)
  if (!is.null(key)) {
    key = check_string(key, "key")
  }
  loro_ephemeral_encode_impl(store@ptr, key)
}

#' @rdname ephemeral
#' @export
ephemeral_apply = function(store, bytes) {
  check_store(store)
  if (!is.raw(bytes)) {
    cli::cli_abort("{.arg bytes} must be a raw vector from {.fn ephemeral_encode}.")
  }
  loro_ephemeral_apply_impl(store@ptr, bytes)
  deliver_events()
  invisible(store)
}

#' @rdname ephemeral
#' @export
ephemeral_remove_outdated = function(store) {
  check_store(store)
  loro_ephemeral_remove_outdated_impl(store@ptr)
  deliver_events()
  invisible(store)
}

#' @rdname ephemeral
#' @export
ephemeral_subscribe = function(store, callback) {
  check_store(store)
  check_callback(callback)
  register_subscription(loro_ephemeral_subscribe_impl(store@ptr), callback)
}

#' @rdname ephemeral
#' @export
ephemeral_subscribe_local_updates = function(store, callback) {
  check_store(store)
  check_callback(callback)
  register_subscription(loro_ephemeral_subscribe_local_updates_impl(store@ptr), callback)
}

S7::method(print, loro_ephemeral_store) = function(x, ...) {
  values = ephemeral_values(x)
  cli::cli_text("{.cls loro_ephemeral_store} {length(values)} entr{?y/ies}")
  if (length(values) > 0) {
    utils::str(values, give.head = FALSE, no.list = TRUE)
  }
  invisible(x)
}
