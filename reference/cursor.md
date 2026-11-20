# Cursors

A cursor is a stable reference to a place in a text or list. A plain
position goes stale as soon as someone edits earlier in the sequence; a
cursor is anchored to a character or element, so it keeps pointing at
the same place as the contents change on any replica.

- `text_cursor()` creates a cursor at the character currently at `pos`;
  `pos = text_length(text) + 1` anchors it to the end of the text.

- `list_cursor()` does the same for the element at `pos` of a list or
  movable list.

- `cursor_pos()` returns the cursor's current 1-based position in `doc`.
  If the anchor character has been deleted, this is the position where
  it used to be.

One limitation applies to movable lists: a cursor on an element cannot
be resolved after that element itself is moved with
[`list_move()`](https://rundel.github.io/creditor/reference/list.md),
and `cursor_pos()` then raises an error. Moving other elements, or
replacing the element with
[`list_set()`](https://rundel.github.io/creditor/reference/list.md), is
fine.

A cursor is a raw vector, so it can be stored or sent to another replica
and resolved there, provided that replica has the edit that created the
anchor character.

## Usage

``` r
text_cursor(text, pos, side = c("middle", "left", "right"))

list_cursor(list, pos, side = c("middle", "left", "right"))

cursor_pos(doc, cursor)
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

  A 1-based character or element position.

- side:

  Which side of the anchor the cursor sticks to when the anchor
  character is deleted: `"middle"` (the default), `"left"`, or
  `"right"`.

- list:

  A list handle, from
  [`doc_list()`](https://rundel.github.io/creditor/reference/containers.md),
  [`doc_movable_list()`](https://rundel.github.io/creditor/reference/containers.md),
  or a parent container. A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  is also accepted and stands for its default root container; see
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md).

- doc:

  A
  [`loro_doc`](https://rundel.github.io/creditor/reference/loro_doc.md)
  holding the container the cursor refers to.

- cursor:

  A raw vector from `text_cursor()` or `list_cursor()`.

## Value

`text_cursor()` and `list_cursor()` return a raw vector and
`cursor_pos()` an integer.

## Examples

``` r
doc = loro_doc()
text = doc_text(doc)
text_insert(text, 1, "world")

cursor = text_cursor(text, 1)
text_insert(text, 1, "Hello ")
cursor_pos(doc, cursor)
#> [1] 7
```
