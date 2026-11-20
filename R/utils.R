check_count = function(x, arg, min, call = rlang::caller_env()) {
  if (
    !is.numeric(x) || length(x) != 1 || is.na(x) || x != trunc(x) ||
      x < min || x > .Machine$integer.max
  ) {
    cli::cli_abort("{.arg {arg}} must be a whole number >= {min}.", call = call)
  }
  as.integer(x)
}

check_string = function(x, arg, call = rlang::caller_env()) {
  if (!is.character(x) || length(x) != 1 || is.na(x)) {
    cli::cli_abort("{.arg {arg}} must be a single string.", call = call)
  }
  as_utf8(x, arg, call = call)
}

# Loro panics on text that is not valid UTF-8, which poisons the document
# and can abort R, so every string is translated and then validated before
# it crosses into Rust. enc2utf8() converts latin1 and native strings but
# passes "bytes" strings and malformed input through unchanged.
as_utf8 = function(x, arg, call = rlang::caller_env()) {
  x = enc2utf8(x)
  if (!all(validUTF8(x))) {
    cli::cli_abort("{.arg {arg}} must be valid UTF-8 text.", call = call)
  }
  x
}

container_types = c("text", "map", "list", "movable_list", "counter", "tree")

check_type = function(type, call = rlang::caller_env()) {
  if (!is.character(type) || length(type) != 1 || !type %in% container_types) {
    cli::cli_abort("{.arg type} must be one of {.or {.val {container_types}}}.", call = call)
  }
  type
}

# Bounds are checked here, in R's 1-based terms, so that errors name the
# position the caller gave. Loro's own messages use 0-based offsets and
# sometimes report the end of a range.
check_insert_pos = function(pos, size, what, arg = "pos", call = rlang::caller_env()) {
  if (pos > size + 1) {
    cli::cli_abort(
      "{.arg {arg}} must be at most {size + 1}, one past the end of the {what}, not {pos}.",
      call = call
    )
  }
  invisible(pos)
}

check_element_pos = function(pos, size, what, arg = "pos", call = rlang::caller_env()) {
  if (pos > size) {
    cli::cli_abort(
      "{.arg {arg}} must be at most {size}, the length of the {what}, not {pos}.",
      call = call
    )
  }
  invisible(pos)
}

check_bool = function(x, arg, call = rlang::caller_env()) {
  if (!is.logical(x) || length(x) != 1 || is.na(x)) {
    cli::cli_abort("{.arg {arg}} must be {.code TRUE} or {.code FALSE}.", call = call)
  }
  x
}

check_strings = function(x, arg, call = rlang::caller_env()) {
  if (!is.character(x) || anyNA(x)) {
    cli::cli_abort("{.arg {arg}} must be a character vector with no missing values.", call = call)
  }
  as_utf8(x, arg, call = call)
}

# Keys to remove or test, given as any number of character vectors.
key_dots = function(..., .call = rlang::caller_env()) {
  keys = unnamed_values(..., .call = .call)
  if (!all(vapply(keys, is.character, logical(1)))) {
    cli::cli_abort("{.arg ...} must be character vectors of keys.", call = .call)
  }
  check_strings(as.character(unlist(keys)), "...", call = .call)
}

check_seconds = function(x, arg, min, call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1 || !is.finite(x) || x < min) {
    cli::cli_abort("{.arg {arg}} must be a number of seconds >= {min}.", call = call)
  }
  round(as.numeric(x) * 1000)
}

# Collects `...` as `key = value` pairs for the functions that write
# several keys at once. Dynamic dots are supported, so a list of values
# can be spliced in with `!!!`.
named_values = function(..., .what = "a key", .call = rlang::caller_env()) {
  values = rlang::list2(...)
  if (length(values) == 0) {
    return(values)
  }
  keys = names(values)
  if (is.null(keys) || anyNA(keys) || any(keys == "")) {
    cli::cli_abort("Each argument in {.arg ...} must be named with {(.what)}.", call = .call)
  }
  keys = as_utf8(keys, "...", call = .call)
  if (anyDuplicated(keys) > 0) {
    cli::cli_abort(
      "Arguments in {.arg ...} must have unique names, but {.val {unique(keys[duplicated(keys)])}} is repeated.",
      call = .call
    )
  }
  names(values) = keys
  values
}

unnamed_values = function(..., .call = rlang::caller_env()) {
  values = rlang::list2(...)
  keys = names(values)
  if (!is.null(keys) && any(keys != "")) {
    cli::cli_abort(
      c(
        "Arguments in {.arg ...} must not be named.",
        i = "To store a map as one element, pass a named list."
      ),
      call = .call
    )
  }
  unname(values)
}

check_positions = function(pos, size, what, call = rlang::caller_env()) {
  if (is.numeric(pos) && length(pos) > size) {
    cli::cli_abort(
      "{.arg pos} names {length(pos)} positions, but the {what} has length {size}.",
      call = call
    )
  }
  if (!is.numeric(pos) || anyNA(pos) || any(pos != trunc(pos)) || any(pos < 1)) {
    cli::cli_abort("{.arg pos} must be a vector of whole numbers >= 1.", call = call)
  }
  if (any(pos > size)) {
    cli::cli_abort(
      "{.arg pos} must be at most {size}, the length of the {what}, not {max(pos)}.",
      call = call
    )
  }
  if (anyDuplicated(pos) > 0) {
    cli::cli_abort("{.arg pos} must not contain duplicates.", call = call)
  }
  as.integer(pos)
}

check_range = function(start, end, size, what, call = rlang::caller_env()) {
  start = check_count(start, "start", 1, call = call)
  end = check_count(end, "end", 0, call = call)
  if (end < start - 1L) {
    cli::cli_abort(
      "{.arg end} must be at least {start - 1L} ({.arg start} - 1, an empty range), not {end}.",
      call = call
    )
  }
  if (end > size) {
    cli::cli_abort(
      c(
        "{.arg start} and {.arg end} must describe a range inside the {what}.",
        x = "The range is {start} to {end}, but the {what} has length {size}."
      ),
      call = call
    )
  }
  list(start = start - 1L, end = end, len = end - start + 1L)
}
