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
    counter = loro_counter(ptr = x$ptr)
  )
}

check_container = function(x, class, arg, call = sys.call(-1)) {
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
#' `doc_list()`, `doc_movable_list()`, and `doc_counter()` return a
#' handle to the root container with the given name, creating it on
#' first use. Handles to nested containers come
#' from [`map_set_container()`], [`list_insert_container()`],
#' [`map_get()`], and [`list_get()`].
#'
#' A handle is a `loro_text`, `loro_map`, `loro_list`,
#' `loro_movable_list`, or `loro_counter` object. Like a
#' [`loro_doc`], it has reference semantics: editing through a handle
#' changes the document it belongs to.
#'
#' * `container_value()` returns the contents of a container: a string
#'   for text, a number for a counter, and a list for a map or list,
#'   with nested containers expanded to their contents.
#' * `container_id()` returns the container's unique id as a string.
#'
#' Root container names are shared across types within a document's
#' value, so use distinct names for different root containers.
#'
#' @param doc A [`loro_doc`].
#' @param name Name of the root container.
#' @param x A container handle.
#'
#' @return `doc_text()`, `doc_map()`, `doc_list()`,
#'   `doc_movable_list()`, and `doc_counter()` return container handles; `container_value()` returns a string or list; and
#'   `container_id()` returns a string.
#'
#' @examples
#' doc = loro_doc()
#'
#' text = doc_text(doc, "body")
#' text_insert(text, 1, "Hello")
#'
#' meta = doc_map(doc, "meta")
#' map_set(meta, "title", "Greeting")
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
container_value = function(x) {
  check_container(x, loro_container, "x")
  loro_container_value_impl(x@ptr)
}

#' @rdname containers
#' @export
container_id = function(x) {
  check_container(x, loro_container, "x")
  loro_container_id_impl(x@ptr)
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
