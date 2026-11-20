loro_container = S7::new_class(
  "loro_container",
  package = "creditor",
  abstract = TRUE,
  properties = list(ptr = S7::class_any)
)

loro_text = S7::new_class("loro_text", parent = loro_container, package = "creditor")
loro_map = S7::new_class("loro_map", parent = loro_container, package = "creditor")
loro_list = S7::new_class("loro_list", parent = loro_container, package = "creditor")
loro_movable_list = S7::new_class("loro_movable_list", parent = loro_list, package = "creditor")
loro_counter = S7::new_class("loro_counter", parent = loro_container, package = "creditor")
loro_tree = S7::new_class("loro_tree", parent = loro_container, package = "creditor")

container_from_ref = function(x) {
  if (!inherits(x, "creditor_container_ref")) {
    return(x)
  }
  switch(
    x$kind,
    text = loro_text(ptr = x$ptr),
    map = loro_map(ptr = x$ptr),
    list = loro_list(ptr = x$ptr),
    movable_list = loro_movable_list(ptr = x$ptr),
    counter = loro_counter(ptr = x$ptr),
    tree = loro_tree(ptr = x$ptr)
  )
}

# A nested assignment such as `map$child$key = value` ends by assigning
# the child handle back to the key it was read from. That step must be a
# no-op: the edit has already been made through the handle.
is_same_child = function(value, current) {
  if (!S7::S7_inherits(value, loro_container)) {
    return(FALSE)
  }
  current = container_from_ref(current)
  if (
    !S7::S7_inherits(current, loro_container) ||
      loro_container_id_impl(current@ptr) != loro_container_id_impl(value@ptr)
  ) {
    cli::cli_abort(
      c(
        "A container handle cannot be stored as a value.",
        i = "Create a child container with {.fn map_set_container} or {.fn list_insert_container}."
      ),
      call = rlang::caller_env()
    )
  }
  TRUE
}

# The pointer for a container argument. A document may be given in place of
# a handle and stands for its root container of that type under the default
# name, so `text_insert(doc, 1, "a")` is `text_insert(doc_text(doc), 1, "a")`.
# Both list types default to the name "list"; a document stands for the
# plain list, so the functions that need a movable list reject it rather
# than quietly working on a second container.
container_ptr = function(x, class, arg, call = rlang::caller_env()) {
  if (!S7::S7_inherits(x, loro_doc)) {
    check_container(x, class, arg, call = call)
    return(x@ptr)
  }
  type = sub("^loro_", "", class@name)
  if (type == "movable_list") {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be a movable list, not a {.cls loro_doc}.",
        i = "A document stands for its plain list. Get a movable list with {.fn doc_movable_list}."
      ),
      call = call
    )
  }
  loro_doc_container_impl(x@ptr, type, type)$ptr
}

check_container = function(x, class, arg, call = rlang::caller_env()) {
  if (!S7::S7_inherits(x, class)) {
    cli::cli_abort(
      "{.arg {arg}} must be a {.cls {class@name}}, not {.obj_type_friendly {x}}.",
      call = call
    )
  }
  invisible(x)
}

#' Container handles
#'
#' @description
#' A document's data lives in containers. `doc_text()`, `doc_map()`,
#' `doc_list()`, `doc_movable_list()`, `doc_counter()`, and `doc_tree()`
#' return a handle to the root container with the given name, creating it on
#' first use. Handles to nested containers come
#' from [`map_set_container()`], [`list_insert_container()`],
#' [`map_get()`], and [`list_get()`].
#'
#' A handle is a `loro_text`, `loro_map`, `loro_list`,
#' `loro_movable_list`, `loro_counter`, or `loro_tree` object. Like a
#' [`loro_doc`], it has reference semantics: editing through a handle
#' changes the document it belongs to.
#'
#' * `container_value()` returns the contents of a container: a string
#'   for text, a number for a counter, and a list for a map or list.
#'   A tree is a list of its root nodes, each a list with `id`, `parent`
#'   (`NA` at the top level), a 1-based `index`, a `fractional_index`
#'   (Loro's internal sort key), `meta`, and `children` (a list of nodes
#'   of the same form). Nested containers are expanded to their contents
#'   by default; with `deep = FALSE` they appear as container id
#'   strings.
#' * `container_is_deleted()` reports whether the container has been
#'   removed from its document, for example because its key was
#'   overwritten or its parent deleted. A handle to a deleted container
#'   can still be read, but editing through it is an error.
#' * `container_id()` returns the container's unique id as a string.
#'
#' Handles also answer to the base functions that fit them: `length()`
#' for text, maps, and lists, `names()`, `$`, and `[[` for maps, `[[`
#' for lists, `as.character()` for text, and `as.list()` for maps and
#' lists.
#'
#' A document can be passed wherever a text, map, list, counter, or tree
#' handle is expected. It stands for its root container of that type
#' under the default name, so `text_insert(doc, 1, "Hello")` is
#' `text_insert(doc_text(doc), 1, "Hello")` and `map_set(doc, a = 1)` is
#' `map_set(doc_map(doc), a = 1)`. This is convenient for a document
#' that holds one container of a kind; use handles for named or nested
#' containers and for movable lists.
#'
#' Root container names are shared across types within a document's
#' value, so use distinct names for different root containers: if two
#' root containers of different types have the same name, each keeps
#' its own contents but [`doc_value()`] shows only one of them.
#'
#' Asking for a root container creates it. Once `doc_map(doc, "notes")`
#' has been called, `doc_value()` includes an empty `notes` entry, on
#' this replica and on any that later import from it, even if nothing
#' is ever stored there. Two replicas with the same edits can therefore
#' differ in which empty root containers their values list.
#'
#' @param doc A [`loro_doc`].
#' @param name Name of the root container.
#' @param x A container handle.
#' @param deep Whether to expand nested containers.
#'
#' @return `doc_text()`, `doc_map()`, `doc_list()`,
#'   `doc_movable_list()`, `doc_counter()`, and `doc_tree()` return
#'   container handles; `container_value()` returns a string, number, or
#'   list; `container_id()` returns a string; and
#'   `container_is_deleted()` returns a logical.
#'
#' @examples
#' doc = loro_doc()
#'
#' text = doc_text(doc, "body")
#' text_insert(text, 1, "Hello")
#'
#' meta = doc_map(doc, "meta")
#' map_set(meta, title = "Greeting")
#'
#' container_value(meta)
#' container_id(text)
#' doc_value(doc)
#'
#' @name containers
NULL

#' @rdname containers
#' @export
doc_text = function(doc, name = "text") {
  check_doc(doc)
  container_from_ref(loro_doc_container_impl(doc@ptr, check_string(name, "name"), "text"))
}

#' @rdname containers
#' @export
doc_map = function(doc, name = "map") {
  check_doc(doc)
  container_from_ref(loro_doc_container_impl(doc@ptr, check_string(name, "name"), "map"))
}

#' @rdname containers
#' @export
doc_list = function(doc, name = "list") {
  check_doc(doc)
  container_from_ref(loro_doc_container_impl(doc@ptr, check_string(name, "name"), "list"))
}

#' @rdname containers
#' @export
doc_movable_list = function(doc, name = "list") {
  check_doc(doc)
  container_from_ref(
    loro_doc_container_impl(doc@ptr, check_string(name, "name"), "movable_list")
  )
}

#' @rdname containers
#' @export
doc_counter = function(doc, name = "counter") {
  check_doc(doc)
  container_from_ref(loro_doc_container_impl(doc@ptr, check_string(name, "name"), "counter"))
}

#' @rdname containers
#' @export
doc_tree = function(doc, name = "tree") {
  check_doc(doc)
  container_from_ref(loro_doc_container_impl(doc@ptr, check_string(name, "name"), "tree"))
}

#' @rdname containers
#' @export
container_value = function(x, deep = TRUE) {
  check_container(x, loro_container, "x")
  check_bool(deep, "deep")
  loro_container_value_impl(x@ptr, deep)
}

#' @rdname containers
#' @export
container_is_deleted = function(x) {
  check_container(x, loro_container, "x")
  loro_container_is_deleted_impl(x@ptr)
}

#' @rdname containers
#' @export
container_id = function(x) {
  check_container(x, loro_container, "x")
  loro_container_id_impl(x@ptr)
}

S7::method(print, loro_tree) = function(x, ...) {
  cli::cli_text("{.cls {class(x)[1]}} {container_id(x)}")
  nodes = tree_nodes(x)
  if (nrow(nodes) == 0) {
    cli::cli_text("(empty)")
  } else {
    print(nodes)
  }
  invisible(x)
}

S7::method(print, loro_container) = function(x, ...) {
  cli::cli_text("{.cls {class(x)[1]}} {container_id(x)}")
  value = container_value(x)
  if (is.character(value) || is.numeric(value)) {
    print(value)
  } else if (length(value) == 0) {
    cli::cli_text("(empty)")
  } else {
    utils::str(value, give.head = FALSE, no.list = TRUE)
  }
  invisible(x)
}
