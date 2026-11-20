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
  as_utf8(x, arg, call = call)
}

# Loro panics on text that is not valid UTF-8, which poisons the document
# and can abort R, so every string is translated and then validated before
# it crosses into Rust. enc2utf8() converts latin1 and native strings but
# passes "bytes" strings and malformed input through unchanged.
as_utf8 = function(x, arg, call = sys.call(-1)) {
  x = enc2utf8(x)
  if (!all(validUTF8(x))) {
    cli::cli_abort("{.arg {arg}} must be valid UTF-8 text.", call = call)
  }
  x
}

container_types = c("text", "map", "list", "movable_list", "counter", "tree")

check_type = function(type, call = sys.call(-1)) {
  if (!is.character(type) || length(type) != 1 || !type %in% container_types) {
    cli::cli_abort("{.arg type} must be one of {.or {.val {container_types}}}.", call = call)
  }
  type
}

# Bounds are checked here, in R's 1-based terms, so that errors name the
# position the caller gave. Loro's own messages use 0-based offsets and
# sometimes report the end of a range. The arithmetic is done in doubles:
# `pos + len` can exceed the integer range.
check_insert_pos = function(pos, size, what, arg = "pos", call = sys.call(-1)) {
  if (pos > size + 1) {
    cli::cli_abort(
      "{.arg {arg}} must be at most {size + 1}, one past the end of the {what}, not {pos}.",
      call = call
    )
  }
  invisible(pos)
}

check_element_pos = function(pos, size, what, arg = "pos", call = sys.call(-1)) {
  if (pos > size) {
    cli::cli_abort(
      "{.arg {arg}} must be at most {size}, the length of the {what}, not {pos}.",
      call = call
    )
  }
  invisible(pos)
}

check_span = function(pos, len, size, what, call = sys.call(-1)) {
  last = as.numeric(pos) + as.numeric(len) - 1
  if (pos > size + 1 || last > size) {
    cli::cli_abort(
      c(
        "{.arg pos} and {.arg len} must describe a range inside the {what}.",
        x = "The range starts at {pos} and has length {len}, but the {what} has length {size}."
      ),
      call = call
    )
  }
  invisible(pos)
}
