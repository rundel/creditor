check_count = function(x, arg, min, call = sys.call(-1)) {
  if (
    !is.numeric(x) || length(x) != 1 || is.na(x) || x != trunc(x) ||
      x < min || x > .Machine$integer.max
  ) {
    cli::cli_abort("{.arg {arg}} must be a whole number >= {min}.", call = call)
  }
  as.integer(x)
}

check_string = function(x, arg, call = sys.call(-1)) {
  if (!is.character(x) || length(x) != 1 || is.na(x)) {
    cli::cli_abort("{.arg {arg}} must be a single string.", call = call)
  }
  enc2utf8(x)
}

container_types = c("text", "map", "list", "movable_list", "counter", "tree")

check_type = function(type, call = sys.call(-1)) {
  if (!is.character(type) || length(type) != 1 || !type %in% container_types) {
    cli::cli_abort("{.arg type} must be one of {.or {.val {container_types}}}.", call = call)
  }
  type
}
