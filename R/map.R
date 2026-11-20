#' Edit maps
#'
#' @description
#' A map holds values under string keys. When replicas set the same key
#' concurrently, one write wins on every replica.
#'
#' * `map_set()` stores values, given as `key = value` arguments. A
#'   value can be a plain R value or a new container from [`loro_text()`],
#'   [`loro_map()`], [`loro_list()`], and the like.
#' * `map_get()` returns the value under `key`, a handle if it is a
#'   container, or `NULL` if the key is absent.
#' * `map_has()` reports whether each of `keys` is present.
#' * `map_ensure_container()` returns the child container under `key`,
#'   creating it if the key is empty. Unlike storing a new container
#'   with `map_set()`, which always makes a fresh one, the container it
#'   creates is
#'   shared: replicas that each create it independently end up editing
#'   the same one, with all their edits merged. Use it for containers
#'   that are created lazily on first use. It is an error if `key`
#'   already holds a plain value, a container of another type, or a
#'   container stored with `map_set()`.
#' * `map_delete()` removes the keys named in `...`, as in
#'   `map_delete(map, "a", "b")` or `map_delete(map, keys)`, and
#'   `map_clear()` removes every key.
#' * `map_last_editor()` returns the peer id of the replica that last
#'   wrote `key`, or `NA` if the key has never been written.
#' * `map_keys()` returns the keys in sorted order, and `map_length()`
#'   the number of entries.
#'
#' A map handle also works with the base functions an R user would
#' reach for with a named list: `map$key` and `map[[key]]` read like
#' `map_get()`, `map$key = value` and `map[[key]] = value` write one
#' key like `map_set()`, `names()` is `map_keys()`, `length()` is
#' `map_length()`, and `as.list()` is [`container_value()`]. As with a
#' list, assigning `NULL` removes the key: `map$key = NULL` is
#' `map_delete(map, "key")`. To store a null, use
#' `map_set(map, key = NULL)`. Assignments can reach through child
#' containers, as in `map$child$key = value`.
#'
#' Loro allows the empty string as a key, and a document written by
#' another Loro client may contain one. It is supported only for
#' compatibility with such documents: it can be read and removed like
#' any other key, but R does not allow an empty argument name, so it
#' cannot be written with `map_set()`. Use `map[[""]] = value` if one
#' has to be changed.
#'
#' @section Values:
#' Plain values are converted as follows. `NULL` and `NA` become null.
#' Length-one logical, numeric, and character vectors become scalars;
#' other unnamed vectors and unnamed lists become lists; named vectors
#' and named lists become maps. Raw vectors are stored as binary, and
#' any names on them are dropped. Objects with a class attribute
#' (factors, dates, data frames) are rejected, and other attributes
#' such as `dim` are ignored.
#'
#' Strings are stored as UTF-8. Strings in another encoding are
#' converted, and strings that are not valid text are rejected. Values
#' may be nested up to 1000 levels deep.
#'
#' An empty vector or list is always stored as an empty list, even if
#' it carries a `names` attribute, so an empty map cannot be written as
#' a plain value.
#'
#' A plain value is stored as a single unit: concurrent changes replace
#' it whole. To let replicas merge edits inside a value, store a child
#' container instead. Values read back as scalars and (possibly nested)
#' lists; map entries are returned sorted by key, comparing the keys
#' byte by byte (as `sort(method = "radix")` does), which is not always
#' the order `sort()` gives in your locale.
#'
#' @param map A map handle, from [`doc_map()`] or a parent container.
#'   A [`loro_doc`] is also accepted and stands for its default root
#'   container; see [`doc_text()`].
#' @param ... Values to store, each named with its key, for example
#'   `map_set(map, title = "Notes", done = FALSE)`: plain values (see the
#'   Values section) or new containers such as `loro_list("a", "b")`. These are [dynamic dots][rlang::dyn-dots], so a named list
#'   can be spliced in with `!!!` and a key held in a variable can be
#'   used with `"{key}" := value`. Values are stored in order, so if one
#'   is rejected the ones before it stay set. For `map_delete()`, the
#'   keys to remove, as strings or character vectors.
#' @param .map A map handle, as for `map`. For `map_set()` the argument
#'   name starts with a dot so that it cannot clash with a key given in
#'   `...`, such as `map_set(x, map = 1)`.
#' @param key A string.
#' @param keys A character vector of keys.
#' @param type Type of the child container: `"text"`, `"map"`,
#'   `"list"`, `"movable_list"`, `"counter"`, or `"tree"`.
#'
#' @return `map_set()` returns `.map` invisibly, and `map_delete()` and
#'   `map_clear()` return `map` invisibly. `map_ensure_container()`
#'   returns a container handle, and `map_last_editor()` a string.
#'   `map_get()` returns a value or handle, `map_has()` a logical vector,
#'   `map_keys()` a character vector, and `map_length()` an integer.
#'
#' @examples
#' doc = loro_doc()
#' meta = doc_map(doc, "meta")
#' map_set(meta, title = "Notes", tags = c("a", "b"))
#'
#' meta$body = loro_text("Hello")
#'
#' map_keys(meta)
#' map_get(meta, "title")
#' meta$title
#' text_get(meta$body)
#'
#' meta$title = "Shopping"
#' map_delete(meta, "tags")
#' as.list(meta)
#'
#' @name map
NULL

#' @rdname map
#' @export
map_set = function(.map, ...) {
  ptr = container_ptr(.map, loro_map, ".map")
  values = named_values(...)
  for (key in names(values)) {
    map_store(ptr, key, values[[key]])
  }
  invisible(.map)
}

#' @rdname map
#' @export
map_ensure_container = function(map, key, type) {
  ptr = container_ptr(map, loro_map, "map")
  key = check_string(key, "key")
  container_from_ref(loro_map_ensure_container_impl(ptr, key, check_type(type)))
}

#' @rdname map
#' @export
map_get = function(map, key) {
  ptr = container_ptr(map, loro_map, "map")
  container_from_ref(loro_map_get_impl(ptr, check_string(key, "key")))
}

#' @rdname map
#' @export
map_has = function(map, keys) {
  ptr = container_ptr(map, loro_map, "map")
  check_strings(keys, "keys") %in% loro_map_keys_impl(ptr)
}

#' @rdname map
#' @export
map_delete = function(map, ...) {
  ptr = container_ptr(map, loro_map, "map")
  for (key in key_dots(...)) {
    loro_map_delete_impl(ptr, key)
  }
  invisible(map)
}

#' @rdname map
#' @export
map_clear = function(map) {
  ptr = container_ptr(map, loro_map, "map")
  loro_map_clear_impl(ptr)
  invisible(map)
}

#' @rdname map
#' @export
map_keys = function(map) {
  ptr = container_ptr(map, loro_map, "map")
  loro_map_keys_impl(ptr)
}

#' @rdname map
#' @export
map_length = function(map) {
  ptr = container_ptr(map, loro_map, "map")
  loro_map_length_impl(ptr)
}

#' @rdname map
#' @export
map_last_editor = function(map, key) {
  ptr = container_ptr(map, loro_map, "map")
  loro_map_last_editor_impl(ptr, check_string(key, "key"))
}

S7::method(`[[`, loro_map) = function(x, i, ...) map_get(x, i)

S7::method(`$`, loro_map) = function(x, name) map_get(x, name)

map_assign = function(map, key, value, call = rlang::caller_env()) {
  ptr = container_ptr(map, loro_map, "map")
  if (is.null(value)) {
    loro_map_delete_impl(ptr, key)
  } else if (!is_same_child(value, loro_map_get_impl(ptr, key))) {
    map_store(ptr, key, value, call = call)
  }
  map
}

# The replacement methods are registered by name in NAMESPACE rather than
# through S7: R 4.4's check of replacement functions errors on S3 methods
# registered as anonymous functions.

#' @rawNamespace S3method("[[<-", "creditor::loro_map", map_subset_assign)
#' @noRd
map_subset_assign = function(x, i, ..., value) {
  map_assign(x, check_string(i, "i"), value)
}

#' @rawNamespace S3method("$<-", "creditor::loro_map", map_dollar_assign)
#' @noRd
map_dollar_assign = function(x, name, value) {
  map_assign(x, check_string(name, "name"), value)
}

S7::method(length, loro_map) = function(x) map_length(x)

S7::method(names, loro_map) = function(x) map_keys(x)

S7::method(as.list, loro_map) = function(x, ...) container_value(x)
