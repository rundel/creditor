#' Edit lists
#'
#' @description
#' A list is an ordered sequence of values. Positions are 1-based.
#' Concurrent insertions at the same position are all kept, in the same
#' order on every replica.
#'
#' * `list_insert()` inserts plain values before the element currently
#'   at `pos`, and `list_push()` appends them. Each argument in `...`
#'   becomes one element.
#' * `list_insert_container()` and `list_push_container()` do the same
#'   with a new, empty child container and return its handle.
#' * `list_get()` returns the element at `pos`, as a handle if it is a
#'   container.
#' * `list_delete()` removes the elements at the positions `pos`, and
#'   `list_clear()` removes them all.
#' * `list_pop()` removes the last element and returns it, or returns
#'   `NULL` if the list is empty. A removed child container is returned
#'   as its contents.
#' * `list_length()` returns the number of elements.
#'
#' A list handle also works with base functions: `list[[pos]]` reads
#' like `list_get()`, `length()` is `list_length()`, and `as.list()` is
#' [`container_value()`]. `list[[pos]] = NULL` removes an element like
#' `list_delete()`, and for a movable list `list[[pos]] = value`
#' replaces one like `list_set()`.
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
#' @param pos A 1-based position. For `list_delete()`, a vector of
#'   positions such as `2:4`.
#' @param ... Plain values to add, one element each. They must not be
#'   named; to store a map as one element, pass a named list. These are
#'   [dynamic dots][rlang::dyn-dots], so a list of elements can be
#'   spliced in with `!!!`.
#' @param value A plain value.
#' @inheritParams map
#'
#' @return `list_insert()`, `list_push()`, `list_delete()`,
#'   `list_clear()`, `list_move()`, and `list_set()` return `list`
#'   invisibly. `list_pop()` returns the removed element.
#'   `list_insert_container()`, `list_push_container()`, and
#'   `list_set_container()` return the new container handle.
#'   `list_get()` returns a value or handle, and `list_length()` an
#'   integer.
#'
#' @examples
#' doc = loro_doc()
#' items = doc_list(doc, "items")
#' list_push(items, "b", "c")
#' list_insert(items, 1, "a")
#'
#' item = list_push_container(items, "map")
#' map_set(item, done = FALSE)
#'
#' list_get(items, 1)
#' items[[2]]
#' list_delete(items, 2:3)
#' as.list(items)
#'
#' tasks = doc_movable_list(doc, "tasks")
#' list_push(tasks, "write", "test", "ship")
#' list_move(tasks, 3, 1)
#' list_set(tasks, 2, "write docs")
#' as.list(tasks)
#'
#' @name list
NULL

#' @rdname list
#' @export
list_insert = function(list, pos, ...) {
  check_container(list, loro_list, "list")
  pos = check_count(pos, "pos", 1)
  values = unnamed_values(...)
  check_insert_pos(pos, loro_list_length_impl(list@ptr), "list")
  for (i in seq_along(values)) {
    loro_list_insert_impl(list@ptr, pos + i - 2L, values[[i]])
  }
  invisible(list)
}

#' @rdname list
#' @export
list_push = function(list, ...) {
  check_container(list, loro_list, "list")
  for (value in unnamed_values(...)) {
    loro_list_insert_impl(list@ptr, loro_list_length_impl(list@ptr), value)
  }
  invisible(list)
}

#' @rdname list
#' @export
list_insert_container = function(list, pos, type) {
  check_container(list, loro_list, "list")
  pos = check_count(pos, "pos", 1)
  type = check_type(type)
  check_insert_pos(pos, loro_list_length_impl(list@ptr), "list")
  container_from_ref(loro_list_insert_container_impl(list@ptr, pos - 1L, type))
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
  check_element_pos(pos, loro_list_length_impl(list@ptr), "list")
  container_from_ref(loro_list_get_impl(list@ptr, pos - 1L))
}

#' @rdname list
#' @export
list_delete = function(list, pos) {
  check_container(list, loro_list, "list")
  pos = sort(check_positions(pos, loro_list_length_impl(list@ptr), "list"))
  if (length(pos) == 0) {
    return(invisible(list))
  }
  run = cumsum(c(TRUE, diff(pos) != 1L))
  for (positions in rev(split(pos, run))) {
    loro_list_delete_impl(list@ptr, positions[1] - 1L, length(positions))
  }
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
  size = loro_list_length_impl(list@ptr)
  check_element_pos(from, size, "list", arg = "from")
  check_element_pos(to, size, "list", arg = "to")
  loro_list_move_impl(list@ptr, from - 1L, to - 1L)
  invisible(list)
}

#' @rdname list
#' @export
list_set = function(list, pos, value) {
  check_container(list, loro_movable_list, "list")
  pos = check_count(pos, "pos", 1)
  check_element_pos(pos, loro_list_length_impl(list@ptr), "list")
  loro_list_set_impl(list@ptr, pos - 1L, value)
  invisible(list)
}

#' @rdname list
#' @export
list_set_container = function(list, pos, type) {
  check_container(list, loro_movable_list, "list")
  pos = check_count(pos, "pos", 1)
  type = check_type(type)
  check_element_pos(pos, loro_list_length_impl(list@ptr), "list")
  container_from_ref(loro_list_set_container_impl(list@ptr, pos - 1L, type))
}

#' @rdname list
#' @export
list_pop = function(list) {
  check_container(list, loro_list, "list")
  loro_list_pop_impl(list@ptr)
}

#' @rdname list
#' @export
list_clear = function(list) {
  check_container(list, loro_list, "list")
  loro_list_clear_impl(list@ptr)
  invisible(list)
}

S7::method(`[[`, loro_list) = function(x, i, ...) list_get(x, i)

S7::method(`[[<-`, loro_list) = function(x, i, ..., value) {
  if (is.null(value)) {
    return(list_delete(x, i))
  }
  current = if (S7::S7_inherits(value, loro_container)) list_get(x, i)
  if (is_same_child(value, current)) x else list_set(x, i, value)
}

S7::method(length, loro_list) = function(x) loro_list_length_impl(x@ptr)

S7::method(as.list, loro_list) = function(x, ...) loro_container_value_impl(x@ptr, TRUE)
