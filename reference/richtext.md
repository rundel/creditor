# Rich text

Marks attach a key and value (a style such as `bold = TRUE`, or data
such as a link target) to a range of text. They merge across replicas
like any other edit. As elsewhere, positions count Unicode code points
and are 1-based, and a range runs from `start` to `end`.

- `text_mark()` marks the characters from `start` to `end` with the
  marks given as `key = value` arguments.

- `text_unmark()` removes the marks named in `keys` from that range.

- `text_delta()` returns the text as a list of runs, each a list with a
  string `insert` and, for marked runs, a named list `attributes`. This
  is the Quill delta format. With `start` and `end` it covers only that
  range. The list has class `loro_delta`, which prints as Markdown (see
  `text_markdown()`) and keeps the plain list structure for
  [`str()`](https://rdrr.io/r/utils/str.html) and indexing. Its
  [`print()`](https://rdrr.io/r/base/print.html) and
  [`format()`](https://rdrr.io/r/base/format.html) methods take a
  `format` argument, one of `"markdown"`, `"html"`, `"ansi"`, or
  `"list"` (the [`str()`](https://rdrr.io/r/utils/str.html) view), whose
  default comes from the `creditor.delta_format` option, so
  `options(creditor.delta_format = "ansi")` changes how deltas
  autoprint. Printing never warns: when the chosen format leaves marks
  out, a note at the end names them.

- `text_markdown()` and `text_html()` render the text with its marks as
  a Markdown or HTML string. Both handle `bold`, `italic`, `underline`,
  `code`, and `link` (whose value is the target URL); Markdown writes
  underline as `<u>` tags. HTML also writes `highlight` as `<mark>` and
  any other mark as a `<span>` with a `data-` attribute holding its
  value, for example `<span data-comment="check this">`. Markdown cannot
  express the other marks, so `text_markdown()` leaves them out with a
  warning.

- `text_ansi()` renders the text for the console with ANSI styles from
  cli: bold, italic, and underline as themselves, `code` in cyan,
  `highlight` on a yellow background, and `link` in blue as a hyperlink
  where the terminal supports one. Other marks have no style and are
  left out with a warning. Styles appear only where cli detects color
  support (see
  [`cli::num_ansi_colors()`](https://cli.r-lib.org/reference/num_ansi_colors.html));
  elsewhere the result is the plain text.

- `text_apply_delta()` edits the text with a list of delta ops. Each op
  is a list with exactly one of `retain` (keep that many characters),
  `insert` (a string), or `delete` (remove that many characters);
  `retain` and `insert` may also carry `attributes`. An attribute set to
  `NULL` removes that mark. The output of `text_delta()` is itself a
  valid delta. A delta that reaches past the end of the text is rejected
  before anything is applied, but if an op fails for another reason
  (such as an unconfigured mark key) the ops before it stay applied.

- `doc_config_text_style()` declares mark keys and how each behaves when
  text is inserted at the edge of a marked range.

## Usage

``` r
text_mark(.text, .start, .end, ...)

text_unmark(text, start, end, keys)

text_delta(text, start = 1, end = text_length(text))

text_markdown(
  text,
  start = 1,
  end = text_length(text),
  marks = NULL,
  strict = FALSE
)

text_ansi(
  text,
  start = 1,
  end = text_length(text),
  marks = NULL,
  strict = FALSE
)

text_html(text, start = 1, end = text_length(text), marks = NULL)

text_apply_delta(text, delta)

doc_config_text_style(.doc, ..., .default = NULL)
```

## Arguments

- .text, .start, .end:

  The text handle and range for `text_mark()`, as for `text`, `start`,
  and `end`. The argument names start with a dot so that they cannot
  clash with a mark key given in `...`.

- ...:

  For `text_mark()`, the marks to apply, each a plain value (see the
  Values section of
  [`map_set()`](https://rundel.github.io/creditor/reference/map.md))
  named with its key, for example `bold = TRUE` or
  `link = "https://loro.dev"`. A key must not contain `":"`, and a value
  of `NULL` or `NA` removes the mark, as `text_unmark()` does. For
  `doc_config_text_style()`, strings giving the expand behavior of each
  key, for example `comment = "none"`. Both are [dynamic
  dots](https://rlang.r-lib.org/reference/dyn-dots.html).

- text:

  A text handle, from
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container. A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  is also accepted and stands for its default root container; see
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md).

- start, end:

  1-based positions of the first and last characters of the range. For
  `text_delta()` and the rendering functions they default to the whole
  text.

- keys:

  A character vector of mark names.

- marks:

  How to render marks, overriding the defaults or covering marks the
  format cannot otherwise show: `NULL`, or a list named by mark key. For
  `text_markdown()` and `text_html()`, each entry is a character vector
  of two strings, the text written before and after the marked range
  (`bold = c(before = "__", after = "__")`; the names are optional), or
  a function that takes the mark's value and returns them
  (`author = \(value) c(before = "<cite>", after = paste0(" (", value, ")</cite>"))`).
  The mark's range decides where they are written. They are written as
  given, without escaping, so a function that puts the value into HTML
  should escape it. For `text_ansi()`, each entry is either two strings
  written before and after the text, or a function that takes the text
  and returns it styled, such as
  [`cli::col_magenta()`](https://cli.r-lib.org/reference/ansi-styles.html);
  a function with an argument named `value` is also given the mark's
  value. A mark with an entry is never left out.

- strict:

  For `text_markdown()` and `text_ansi()`, whether leaving out a mark
  the format cannot show is an error rather than a warning. Both
  conditions have class `creditor_dropped_marks`, so the warning can be
  silenced on its own with
  [`suppressWarnings(classes = "creditor_dropped_marks")`](https://rdrr.io/r/base/warning.html).

- delta:

  A list of delta ops.

- .doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).
  The argument name starts with a dot so that it cannot clash with a
  mark key given in `...`.

- .default:

  Expand behavior for keys that are not configured, or `NULL` to reject
  them.

## Value

`text_mark()` returns `.text` invisibly, `text_unmark()` and
`text_apply_delta()` return `text` invisibly, `text_delta()` returns a
`loro_delta` list, `text_markdown()` and `text_html()` return a string,
`text_ansi()` returns a
[`cli::ansi_string()`](https://cli.r-lib.org/reference/ansi_string.html),
and `doc_config_text_style()` returns `.doc` invisibly.

## Style configuration

A key must be configured before it can be used in a mark. New documents
know these keys: `bold`, `italic`, and `underline` (which expand
`"after"`), and `link`, `highlight`, `comment`, and `code` (which expand
`"none"`).

The expand behavior decides whether text inserted at a boundary of a
marked range joins the mark: `"after"` for text inserted at its end,
`"before"` at its start, `"both"`, or `"none"`.

Each call to `doc_config_text_style()` sets the complete configuration:
the built-in keys, overridden or extended by the keys given in `...`.
The configuration is local to a replica and is not synchronized, so
every replica should configure a key the same way.

## Examples

``` r
doc = loro_doc()
text = doc_text(doc)
text_insert(text, 1, "Hello world")
text_mark(text, 1, 5, bold = TRUE)
text_mark(text, 7, 11, link = "https://loro.dev", italic = TRUE)
text_unmark(text, 7, 11, "italic")
text_delta(text)
#> <loro_delta>
#> **Hello** [world](https://loro.dev)
print(text_delta(text), format = "html")
#> <loro_delta>
#> <strong>Hello</strong> <a href="https://loro.dev">world</a>
str(text_delta(text))
#> List of 3
#>  $ :List of 2
#>   ..$ insert    : chr "Hello"
#>   ..$ attributes:List of 1
#>   .. ..$ bold: logi TRUE
#>  $ :List of 1
#>   ..$ insert: chr " "
#>  $ :List of 2
#>   ..$ insert    : chr "world"
#>   ..$ attributes:List of 1
#>   .. ..$ link: chr "https://loro.dev"
text_markdown(text)
#> [1] "**Hello** [world](https://loro.dev)"
text_html(text)
#> [1] "<strong>Hello</strong> <a href=\"https://loro.dev\">world</a>"
text_markdown(text, marks = list(bold = c(before = "__", after = "__")))
#> [1] "__Hello__ [world](https://loro.dev)"
cat(text_ansi(text), "\n")
#> Hello world 

text_apply_delta(text, list(
  list(retain = 5),
  list(insert = ",", attributes = list(bold = TRUE)),
  list(delete = 1)
))
text_get(text)
#> [1] "Hello,world"

doc_config_text_style(doc, author = "none")
text_mark(text, 1, 5, author = "cr")
```
