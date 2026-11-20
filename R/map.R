#' Edit maps
#'
#' @description
#' A map holds values under string keys. When replicas set the same key
#' concurrently, one write wins on every replica.
#'
#' * `map_set()` stores a plain value under `key`.
#' * `map_set_container()` stores a new, empty child container under
#'   `key` and returns its handle.
#' * `map_get()` returns the value under `key`, a handle if it is a
#'   container, or `NULL` if the key is absent.
#' * `map_delete()` removes `key`.
#' * `map_keys()` returns the keys in sorted order, and `map_length()`
#'   the number of entries.
#'
#' @section Values:
#' Plain values are converted as follows. `NULL` and `NA` become null.
#' Length-one logical, numeric, and character vectors become scalars;
#' other unnamed vectors and unnamed lists become lists; named vectors
#' and named lists become maps. Raw vectors are stored as binary.
#' Objects with a class attribute (factors, dates, data frames) are
#' rejected.
#'
#' A plain value is stored as a single unit: concurrent changes replace
#' it whole. To let replicas merge edits inside a value, store a child
#' container instead. Values read back as scalars and (possibly nested)
#' lists; map entries are returned in sorted key order.
#'
#' @param map A map handle, from [`doc_map()`] or a parent container.
#' @param key A string.
#' @param value A plain value; see the Values section.
#' @param type Type of the child container: `"text"`, `"map"`, or
#'   `"list"`.
#'
#' @return `map_set()` and `map_delete()` return `map` invisibly.
#'   `map_set_container()` returns the new container handle. `map_get()`
#'   returns a value or handle, `map_keys()` a character vector, and
#'   `map_length()` an integer.
#'
#' @examples
#' doc = loro_doc()
#' meta = doc_map(doc, "meta")
#' map_set(meta, "title", "Notes")
#' map_set(meta, "tags", c("a", "b"))
#'
#' body = map_set_container(meta, "body", "text")
#' text_insert(body, 1, "Hello")
#'
#' map_keys(meta)
#' map_get(meta, "title")
#' text_get(map_get(meta, "body"))
#' container_value(meta)
#'
#' @name map
NULL

#' @rdname map
#' @export
map_set = function(map, key, value) {
  check_container(map, loro_map, "map")
  loro_map_set_impl(map@ptr, check_string(key, "key"), value)
  invisible(map)
}

#' @rdname map
#' @export
map_set_container = function(map, key, type) {
  check_container(map, loro_map, "map")
  key = check_string(key, "key")
  container_from_ref(loro_map_set_container_impl(map@ptr, key, check_type(type)))
}

#' @rdname map
#' @export
map_get = function(map, key) {
  check_container(map, loro_map, "map")
  container_from_ref(loro_map_get_impl(map@ptr, check_string(key, "key")))
}

#' @rdname map
#' @export
map_delete = function(map, key) {
  check_container(map, loro_map, "map")
  loro_map_delete_impl(map@ptr, check_string(key, "key"))
  invisible(map)
}

#' @rdname map
#' @export
map_keys = function(map) {
  check_container(map, loro_map, "map")
  loro_map_keys_impl(map@ptr)
}

#' @rdname map
#' @export
map_length = function(map) {
  check_container(map, loro_map, "map")
  loro_map_length_impl(map@ptr)
}
