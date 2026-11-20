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
  range.

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
text_mark(text, start, end, ...)

text_unmark(text, start, end, keys)

text_delta(text, start = 1, end = text_length(text))

text_apply_delta(text, delta)

doc_config_text_style(doc, ..., .default = NULL)
```

## Arguments

- text:

  A text handle, from
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container. A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  is also accepted and stands for its default root container; see
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md).

- start, end:

  1-based positions of the first and last characters of the range. For
  `text_delta()` they default to the whole text.

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

- keys:

  A character vector of mark names.

- delta:

  A list of delta ops.

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- .default:

  Expand behavior for keys that are not configured, or `NULL` to reject
  them.

## Value

`text_mark()`, `text_unmark()`, and `text_apply_delta()` return `text`
invisibly; `text_delta()` returns a list; and `doc_config_text_style()`
returns `doc` invisibly.

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
