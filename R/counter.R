#' Counters
#'
#' @description
#' A counter holds a number that replicas change by adding to it. When
#' replicas increment concurrently, every increment is kept and the
#' results add up. A number stored with [`map_set()`] would instead
#' keep only one replica's value.
#'
#' * `counter_increment()` adds `by` to the counter; a negative value
#'   subtracts.
#' * `counter_get()` returns the current value.
#'
#' @param counter A counter handle, from [`doc_counter()`] or a parent
#'   container.
#'   A [`loro_doc`] is also accepted and stands for its default root
#'   container; see [`doc_text()`].
#' @param by A number to add.
#'
#' @return `counter_increment()` returns `counter` invisibly and
#'   `counter_get()` a number.
#'
#' @examples
#' doc = loro_doc()
#' votes = doc_counter(doc, "votes")
#' counter_increment(votes)
#' counter_increment(votes, 2)
#' counter_get(votes)
#'
#' @name counter
NULL

#' @rdname counter
#' @export
counter_increment = function(counter, by = 1) {
  ptr = container_ptr(counter, loro_counter, "counter")
  if (!is.numeric(by) || length(by) != 1 || !is.finite(by)) {
    cli::cli_abort("{.arg by} must be a single finite number.")
  }
  loro_counter_increment_impl(ptr, as.numeric(by))
  invisible(counter)
}

#' @rdname counter
#' @export
counter_get = function(counter) {
  ptr = container_ptr(counter, loro_counter, "counter")
  loro_container_value_impl(ptr, TRUE)
}
