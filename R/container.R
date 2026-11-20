loro_container = S7::new_class(
  "loro_container",
  package = "creditor",
  abstract = TRUE,
  properties = list(ptr = S7::class_any)
)

#' Create containers
#'
#' @description
#' These functions create a container that does not yet belong to a
#' document. Store it in a map or list, the way a nested list is built in
#' R, and it becomes part of that document:
#'
#' ```r
#' note = doc_map(doc, "note")
#' note$items = loro_list("milk", "eggs")
#' note$body = loro_text("Buy before Friday")
#' ```
#'
#' Containers nest, so `loro_map(title = "Notes", tags = loro_list("a"))`
#' builds a map holding a list, and all of it is added in one step when
#' it is stored. Wherever a value can be stored (`map_set()`, `$<-` and
#' `[[<-` on a map, `list_insert()`, `list_push()`, `list_set()`, and
#' `[[<-` on a list), a new container can be given instead.
#'
#' A new container can be edited with the usual functions before it is
#' stored. Storing it adds a copy of its contents to the document, and
#' from then on the handle, and any handle to a container nested in it,
#' refers to the container in the document, so later edits through it
#' are part of the document's history and sync like any other.
#'
#' A container can be stored only once. Storing a handle to a container
#' that is already in a document is an error, except for assigning a
#' child back to the key it was read from (as in `map$child$key = value`),
#' which does nothing.
#'
#' The objects returned are the handle classes described in
#' [`containers`].
#'
#' @param value For `loro_text()`, the initial text, a string. For
#'   `loro_counter()`, the initial value, a number.
#' @param ... For `loro_map()`, values named by key, as in [`map_set()`].
#'   For `loro_list()` and `loro_movable_list()`, unnamed elements, as in
#'   [`list_push()`]. Values may themselves be new containers.
#' @param .ptr For internal use.
#'
#' @return A container handle that does not belong to a document until it
#'   is stored.
#'
#' @examples
#' doc = loro_doc()
#' note = doc_map(doc, "note")
#'
#' note$title = "Groceries"
#' note$items = loro_list("milk", "eggs")
#' note$body = loro_text("Buy before Friday")
#' str(doc_value(doc))
#'
#' list_push(note$items, "bread")
#' text_push(note$body, "!")
#'
#' map_set(doc, todo = loro_list(
#'   loro_map(task = "write", done = TRUE),
#'   loro_map(task = "test", done = FALSE)
#' ))
#' doc_get(doc, "map", "todo", 2, "task")
#'
#' @name loro_text
#' @export
loro_text = S7::new_class(
  "loro_text",
  parent = loro_container,
  package = "creditor",
  constructor = function(value = "", .ptr = NULL) {
    if (!is.null(.ptr)) {
      return(S7::new_object(S7::S7_object(), ptr = .ptr))
    }
    value = check_string(value, "value")
    ptr = new_container_ptr("text")
    if (nzchar(value)) {
      loro_text_insert_impl(ptr, 0L, value)
    }
    S7::new_object(S7::S7_object(), ptr = ptr)
  }
)

#' @rdname loro_text
#' @export
loro_map = S7::new_class(
  "loro_map",
  parent = loro_container,
  package = "creditor",
  constructor = function(..., .ptr = NULL) {
    if (!is.null(.ptr)) {
      return(S7::new_object(S7::S7_object(), ptr = .ptr))
    }
    values = named_values(..., .call = rlang::current_env())
    map = S7::new_object(S7::S7_object(), ptr = new_container_ptr("map"))
    map_set(map, !!!values)
    map
  }
)

#' @rdname loro_text
#' @export
loro_list = S7::new_class(
  "loro_list",
  parent = loro_container,
  package = "creditor",
  constructor = function(..., .ptr = NULL) {
    if (!is.null(.ptr)) {
      return(S7::new_object(S7::S7_object(), ptr = .ptr))
    }
    values = unnamed_values(..., .call = rlang::current_env())
    list = S7::new_object(S7::S7_object(), ptr = new_container_ptr("list"))
    list_push(list, !!!values)
    list
  }
)

#' @rdname loro_text
#' @export
loro_movable_list = S7::new_class(
  "loro_movable_list",
  parent = loro_list,
  package = "creditor",
  constructor = function(..., .ptr = NULL) {
    if (!is.null(.ptr)) {
      return(S7::new_object(loro_list(.ptr = .ptr)))
    }
    values = unnamed_values(..., .call = rlang::current_env())
    list = S7::new_object(loro_list(.ptr = new_container_ptr("movable_list")))
    list_push(list, !!!values)
    list
  }
)

#' @rdname loro_text
#' @export
loro_counter = S7::new_class(
  "loro_counter",
  parent = loro_container,
  package = "creditor",
  constructor = function(value = 0, .ptr = NULL) {
    if (!is.null(.ptr)) {
      return(S7::new_object(S7::S7_object(), ptr = .ptr))
    }
    counter = S7::new_object(S7::S7_object(), ptr = new_container_ptr("counter"))
    if (!identical(value, 0)) {
      counter_increment(counter, value)
    }
    counter
  }
)

#' @rdname loro_text
#' @export
loro_tree = S7::new_class(
  "loro_tree",
  parent = loro_container,
  package = "creditor",
  constructor = function(.ptr = NULL) {
    if (is.null(.ptr)) {
      .ptr = new_container_ptr("tree")
    }
    S7::new_object(S7::S7_object(), ptr = .ptr)
  }
)

# The pointer of a container handle, which must not be a document.
handle_ptr = function(x, call = rlang::caller_env()) {
  check_container(x, loro_container, "x", call = call)
  loro_container_resolve_impl(x@ptr)
  x@ptr
}

new_container_ptr = function(type) {
  loro_container_new_impl(type)$ptr
}

container_from_ref = function(x) {
  if (!inherits(x, "creditor_container_ref")) {
    return(x)
  }
  switch(
    x$kind,
    text = loro_text(.ptr = x$ptr),
    map = loro_map(.ptr = x$ptr),
    list = loro_list(.ptr = x$ptr),
    movable_list = loro_movable_list(.ptr = x$ptr),
    counter = loro_counter(.ptr = x$ptr),
    tree = loro_tree(.ptr = x$ptr)
  )
}

# A nested assignment such as `map$child$key = value` ends by assigning
# the child handle back to the key it was read from. That step must be a
# no-op: the edit has already been made through the handle. Any other
# handle that is already in a document cannot be stored again.
is_same_child = function(value, current) {
  if (!S7::S7_inherits(value, loro_container) || !loro_container_resolve_impl(value@ptr)) {
    return(FALSE)
  }
  current = container_from_ref(current)
  if (
    !S7::S7_inherits(current, loro_container) ||
      loro_container_id_impl(current@ptr) != loro_container_id_impl(value@ptr)
  ) {
    abort_attached(call = rlang::caller_env())
  }
  TRUE
}

abort_attached = function(call) {
  cli::cli_abort(
    c(
      "A container that is already in a document cannot be stored again.",
      i = "Store a new container instead, such as {.code loro_list()} or {.code loro_text()}."
    ),
    call = call
  )
}

# The pointer of a new container to attach, or NULL for a plain value.
attachable = function(value, call = rlang::caller_env()) {
  if (!S7::S7_inherits(value, loro_container)) {
    return(NULL)
  }
  if (loro_container_resolve_impl(value@ptr)) {
    abort_attached(call = call)
  }
  value@ptr
}

map_store = function(ptr, key, value, call = rlang::caller_env()) {
  child = attachable(value, call = call)
  if (is.null(child)) {
    loro_map_set_impl(ptr, key, value)
  } else {
    loro_map_attach_impl(ptr, key, child)
  }
}

list_store = function(ptr, pos, value, call = rlang::caller_env()) {
  child = attachable(value, call = call)
  if (is.null(child)) {
    loro_list_insert_impl(ptr, pos, value)
  } else {
    loro_list_attach_impl(ptr, pos, child)
  }
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
    loro_container_resolve_impl(x@ptr)
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
#' first use. Handles to nested containers come from [`map_get()`] and
#' [`list_get()`] (or `$` and `[[`), and new containers to nest are made
#' with [`loro_text()`], [`loro_map()`], [`loro_list()`], and the like.
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
  ptr = handle_ptr(x)
  check_bool(deep, "deep")
  loro_container_value_impl(ptr, deep)
}

#' @rdname containers
#' @export
container_is_deleted = function(x) {
  ptr = handle_ptr(x)
  loro_container_is_deleted_impl(ptr)
}

#' @rdname containers
#' @export
container_id = function(x) {
  ptr = handle_ptr(x)
  loro_container_id_impl(ptr)
}

print_header = function(x) {
  if (loro_container_resolve_impl(x@ptr)) {
    cli::cli_text("{.cls {class(x)[1]}} {container_id(x)}")
  } else {
    cli::cli_text("{.cls {class(x)[1]}} (not yet in a document)")
  }
}

S7::method(print, loro_tree) = function(x, ...) {
  print_header(x)
  nodes = tree_nodes(x)
  if (nrow(nodes) == 0) {
    cli::cli_text("(empty)")
  } else {
    print(nodes)
  }
  invisible(x)
}

S7::method(print, loro_container) = function(x, ...) {
  print_header(x)
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
