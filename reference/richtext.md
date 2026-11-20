# Rich text

Marks attach a key and value (a style such as `bold = TRUE`, or data
such as a link target) to a range of text. They merge across replicas
like any other edit. As elsewhere, positions and lengths count Unicode
code points and are 1-based.

- `text_mark()` marks `len` characters starting at `pos` with
  `key = value`.

- `text_unmark()` removes the mark `key` from that range.

- `text_delta()` returns the text as a list of runs, each a list with a
  string `insert` and, for marked runs, a named list `attributes`. This
  is the Quill delta format. With `pos` and `len` it covers only that
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
text_mark(text, pos, len, key, value = TRUE)

text_unmark(text, pos, len, key)

text_delta(text, pos = NULL, len = NULL)

text_apply_delta(text, delta)

doc_config_text_style(doc, ..., default = NULL)
```

## Arguments

- text:

  A text handle, from
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container.

- pos:

  A 1-based character position.

- len:

  Number of characters to mark, unmark, or return. For `text_delta()`,
  `pos` and `len` are optional and must be given together.

- key:

  Name of the mark. It must not contain `":"`.

- value:

  A plain value for the mark; see the Values section of
  [`map_set()`](https://rundel.github.io/creditor/reference/map.md).
  `NULL` and `NA` remove the mark, as `text_unmark()` does.

- delta:

  A list of delta ops.

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md).

- ...:

  Named strings giving the expand behavior for each key, for example
  `comment = "none"`.

- default:

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
text_mark(text, 1, 5, "bold")
text_mark(text, 7, 5, "link", "https://loro.dev")
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
text_mark(text, 1, 5, "author", "cr")
```
