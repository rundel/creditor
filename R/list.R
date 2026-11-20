#' Edit lists
#'
#' @description
#' A list is an ordered sequence of values. Positions are 1-based.
#' Concurrent insertions at the same position are all kept, in the same
#' order on every replica.
#'
#' * `list_insert()` inserts a plain value before the element currently
#'   at `pos`, and `list_push()` appends one.
#' * `list_insert_container()` and `list_push_container()` do the same
#'   with a new, empty child container and return its handle.
#' * `list_get()` returns the element at `pos`, as a handle if it is a
#'   container.
#' * `list_delete()` removes `len` elements starting at `pos`.
#' * `list_length()` returns the number of elements.
#'
#' A movable list, from [`doc_movable_list()`], works with all of the
#' functions above and adds two operations that merge cleanly across
#' replicas. In a plain list they can only be imitated by deleting and
#' re-inserting, which duplicates the element when two replicas do it
#' at once.
#'
#' * `list_move()` moves the element at `from` so that it ends up at
#'   position `to`. Concurrent moves of one element leave a single copy.
#' * `list_set()` replaces the element at `pos` in place, and
#'   `list_set_container()` replaces it with a new, empty child
#'   container. Concurrent sets resolve to one winner.
#'
#' Plain values are converted as described in the Values section of
#' [`map_set()`].
#'
#' @param list A list handle, from [`doc_list()`], [`doc_movable_list()`],
#'   or a parent container. `list_move()`, `list_set()`, and
#'   `list_set_container()` need a movable list.
#' @param from,to 1-based positions.
#' @param pos A 1-based position.
#' @param value A plain value.
#' @param len Number of elements to delete.
#' @inheritParams map
#'
#' @return `list_insert()`, `list_push()`, `list_delete()`,
#'   `list_move()`, and `list_set()` return `list` invisibly.
#'   `list_insert_container()`, `list_push_container()`, and
#'   `list_set_container()` return the new container handle.
#'   `list_get()` returns a value or handle, and `list_length()` an
#'   integer.
#'
#' @examples
#' doc = loro_doc()
#' items = doc_list(doc, "items")
#' list_push(items, "b")
#' list_insert(items, 1, "a")
#'
#' item = list_push_container(items, "map")
#' map_set(item, "done", FALSE)
#'
#' list_get(items, 1)
#' list_delete(items, 2)
#' container_value(items)
#'
#' tasks = doc_movable_list(doc, "tasks")
#' list_push(tasks, "write")
#' list_push(tasks, "test")
#' list_push(tasks, "ship")
#' list_move(tasks, 3, 1)
#' list_set(tasks, 2, "write docs")
#' container_value(tasks)
#'
#' @name list
NULL

#' @rdname list
#' @export
list_insert = function(list, pos, value) {
  check_container(list, loro_list, "list")
  pos = check_count(pos, "pos", 1)
  loro_list_insert_impl(list@ptr, pos - 1L, value)
  invisible(list)
}

#' @rdname list
#' @export
list_push = function(list, value) {
  check_container(list, loro_list, "list")
  loro_list_insert_impl(list@ptr, loro_list_length_impl(list@ptr), value)
  invisible(list)
}

#' @rdname list
#' @export
list_insert_container = function(list, pos, type) {
  check_container(list, loro_list, "list")
  pos = check_count(pos, "pos", 1)
  container_from_ref(loro_list_insert_container_impl(list@ptr, pos - 1L, check_type(type)))
}

#' @rdname list
#' @export
list_push_container = function(list, type) {
  check_container(list, loro_list, "list")
  pos = loro_list_length_impl(list@ptr)
  container_from_ref(loro_list_insert_container_impl(list@ptr, pos, check_type(type)))
}

#' @rdname list
#' @export
list_get = function(list, pos) {
  check_container(list, loro_list, "list")
  pos = check_count(pos, "pos", 1)
  container_from_ref(loro_list_get_impl(list@ptr, pos - 1L))
}

#' @rdname list
#' @export
list_delete = function(list, pos, len = 1) {
  check_container(list, loro_list, "list")
  pos = check_count(pos, "pos", 1)
  len = check_count(len, "len", 0)
  loro_list_delete_impl(list@ptr, pos - 1L, len)
  invisible(list)
}

#' @rdname list
#' @export
list_length = function(list) {
  check_container(list, loro_list, "list")
  loro_list_length_impl(list@ptr)
}

#' @rdname list
#' @export
list_move = function(list, from, to) {
  check_container(list, loro_movable_list, "list")
  from = check_count(from, "from", 1)
  to = check_count(to, "to", 1)
  loro_list_move_impl(list@ptr, from - 1L, to - 1L)
  invisible(list)
}

#' @rdname list
#' @export
list_set = function(list, pos, value) {
  check_container(list, loro_movable_list, "list")
  pos = check_count(pos, "pos", 1)
  loro_list_set_impl(list@ptr, pos - 1L, value)
  invisible(list)
}

#' @rdname list
#' @export
list_set_container = function(list, pos, type) {
  check_container(list, loro_movable_list, "list")
  pos = check_count(pos, "pos", 1)
  container_from_ref(loro_list_set_container_impl(list@ptr, pos - 1L, check_type(type)))
}
