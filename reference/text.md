# Edit collaborative text

Positions count Unicode code points and are 1-based, and a range of text
is given by the positions of its first and last characters, `start` and
`end`, as in [`substr()`](https://rdrr.io/r/base/substr.html). An empty
range has `end = start - 1`.

- `text_insert()` inserts `value` before the character currently at
  `pos`; `text_push()` appends it to the end.

- `text_delete()` removes the characters from `start` to `end`.

- `text_replace()` replaces the characters from `start` to `end` with
  `value`, as a deletion followed by an insertion.

- `text_update()` changes the text to `value` by computing a diff and
  applying only the insertions and deletions needed, so concurrent edits
  elsewhere in the text, marks, and cursors survive. With `by = "line"`
  the diff treats each line as a unit, which is faster for long texts
  but replaces a line whole when any part of it changes.

- `text_sub()` returns the characters from `start` to `end`.

- `text_get()` returns the current contents as a string, as does
  [`as.character()`](https://rdrr.io/r/base/character.html).

- `text_length()` returns the number of characters, or the length in
  another `unit`. [`length()`](https://rdrr.io/r/base/length.html) of a
  text handle is its number of characters.

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

text_push(text, value)

text_delete(text, start, end)

text_update(text, value, by = c("char", "line"))

text_replace(text, start, end, value)

text_sub(text, start = 1, end = text_length(text))

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
  or a parent container. A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  is also accepted and stands for its default root container; see
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md).

- pos:

  A 1-based character position.

- value:

  A string: the text to insert, or the new contents for `text_update()`.

- start, end:

  1-based positions of the first and last characters of a range. For
  `text_sub()` they default to the whole text.

- by:

  Whether `text_update()` compares the old and new text character by
  character (`"char"`) or line by line (`"line"`).

- unit, from, to:

  A unit for counting: `"unicode"` (code points, used everywhere else in
  this package), `"utf16"` (UTF-16 code units), or `"utf8"` (bytes).

## Value

`text_insert()`, `text_push()`, `text_delete()`, `text_replace()`, and
`text_update()` return `text` invisibly. `text_sub()` and `text_get()`
return a string, and `text_convert_pos()` and `text_length()` an
integer.

## Examples

``` r
doc = loro_doc()
text = doc_text(doc)
text_insert(text, 1, "Hello world")
text_push(text, "!")
text_sub(text, 1, 5)
#> [1] "Hello"
text_delete(text, 1, 6)
text_get(text)
#> [1] "world!"
text_length(text)
#> [1] 6

text_update(text, "brave new world")
text_get(text)
#> [1] "brave new world"
```
