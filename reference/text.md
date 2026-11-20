# Edit collaborative text

Positions and lengths count Unicode code points and are 1-based,
matching [`substr()`](https://rdrr.io/r/base/substr.html).

- `text_insert()` inserts `value` before the character currently at
  `pos`; `pos = text_length(text) + 1` appends.

- `text_delete()` removes `len` characters starting at `pos`.

- `text_splice()` replaces `len` characters starting at `pos` with
  `value`, as a deletion followed by an insertion.

- `text_update()` changes the text to `value` by computing a diff and
  applying only the insertions and deletions needed, so concurrent edits
  elsewhere in the text, marks, and cursors survive. With `by = "line"`
  the diff treats each line as a unit, which is faster for long texts
  but replaces a line whole when any part of it changes.

- `text_slice()` returns `len` characters starting at `pos`.

- `text_get()` returns the current contents as a string.

- `text_length()` returns the number of characters, or the length in
  another `unit`.

- `text_convert_pos()` converts a position between units, for exchanging
  positions with software that counts differently: JavaScript, and so
  browser-based editors, counts UTF-16 code units, in which a character
  outside the basic plane (most emoji) counts as two. Positions stay
  1-based in every unit, so subtract 1 to get a 0-based JavaScript
  offset. A position in the middle of a character converts to the
  position of that character, and the result is `NA` if `pos` is out of
  range.

## Usage

``` r
text_insert(text, pos, value)

text_delete(text, pos, len)

text_update(text, value, by = c("char", "line"))

text_splice(text, pos, len, value)

text_slice(text, pos, len)

text_get(text)

text_length(text, unit = c("unicode", "utf16", "utf8"))

text_convert_pos(
  text,
  pos,
  from = c("unicode", "utf16", "utf8"),
  to = c("utf16", "unicode", "utf8")
)
```

## Arguments

- text:

  A text handle, from
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container.

- pos:

  A 1-based character position.

- value:

  A string: the text to insert, or the new contents for `text_update()`.

- len:

  Number of characters to delete, replace, or return.

- by:

  Whether `text_update()` compares the old and new text character by
  character (`"char"`) or line by line (`"line"`).

- unit, from, to:

  A unit for counting: `"unicode"` (code points, used everywhere else in
  this package), `"utf16"` (UTF-16 code units), or `"utf8"` (bytes).

## Value

`text_insert()`, `text_delete()`, `text_splice()`, and `text_update()`
return `text` invisibly, `text_slice()` a string, `text_convert_pos()`
an integer, `text_get()` a string, and `text_length()` an integer.

## Examples

``` r
doc = loro_doc()
text = doc_text(doc)
text_insert(text, 1, "Hello world")
text_delete(text, 1, 6)
text_get(text)
#> [1] "world"
text_length(text)
#> [1] 5

text_update(text, "brave new world")
text_get(text)
#> [1] "brave new world"
```
