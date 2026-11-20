# Container types

A Loro document is a collection of containers. Each container type holds
a different shape of data and, more importantly, resolves concurrent
edits in a different way. Choosing a container is mostly a matter of
deciding what should happen when two people change the same thing at
once.

This vignette walks through every container type creditor supports:
text, map, list, movable list, counter, and tree. Each section shows the
basic operations and then what happens when two replicas edit
concurrently and merge.

## Setup

A replica is a copy of a document that can be edited independently. Two
small helpers keep the examples short. `replica()` makes a second copy
of a document under its own peer id, and `sync()` uses
[`doc_merge()`](https://rundel.github.io/creditor/reference/doc_sync.md)
to give each side the changes it is missing, returning the first
document.

``` r
library(creditor)

replica = function(doc, peer_id) {
  doc_fork(doc) |>
    doc_set_peer_id(peer_id)
}

sync = function(a, b) {
  doc_merge(b, a)
  doc_merge(a, b)
}
```

Every example follows the same pattern: create a document, make a
replica, edit both without communicating, and then sync. After a sync
the two replicas always hold the same contents. What differs between
container types is what those contents are.

Containers are reached through handles.
[`doc_text()`](https://rundel.github.io/creditor/reference/containers.md),
[`doc_map()`](https://rundel.github.io/creditor/reference/containers.md),
[`doc_list()`](https://rundel.github.io/creditor/reference/containers.md),
[`doc_movable_list()`](https://rundel.github.io/creditor/reference/containers.md),
[`doc_counter()`](https://rundel.github.io/creditor/reference/containers.md),
and
[`doc_tree()`](https://rundel.github.io/creditor/reference/containers.md)
each return a handle to a named root container, creating it on first
use. Handles have reference semantics: editing through a handle changes
the document.

A document that needs only one container of a kind can skip the handle.
Every function that takes a handle also takes the document itself, which
then stands for its root container of that type under the default name:
`text_insert(doc, 1, "Hello")` is short for
`text_insert(doc_text(doc), 1, "Hello")`. Most examples below use this
form, and switch to handles for named and nested containers.

Editing functions return the document or handle they were given,
invisibly, so a series of edits can be written as a pipeline. Functions
that read something, such as
[`text_get()`](https://rundel.github.io/creditor/reference/text.md) or
[`doc_value()`](https://rundel.github.io/creditor/reference/doc.md), end
a pipeline.

## Text

A text container holds a string that can be edited by inserting and
deleting at character positions. Positions are 1-based and count Unicode
code points.

``` r
loro_doc(peer_id = 1) |>
  text_insert(1, "The quick fox") |>
  text_insert(11, "brown ") |>
  text_delete(1, 4) |>
  text_get()
#> [1] "quick brown fox"
```

Concurrent edits to different parts of a text are all kept. Here one
replica changes the start of a sentence while the other changes the end.

``` r
a = loro_doc(peer_id = 1) |>
  text_insert(1, "The quick fox jumps")
b = replica(a, peer_id = 2)

text_replace(a, 1, 3, "A")
text_insert(b, 20, " over the dog")

sync(a, b) |>
  text_get()
#> [1] "A quick fox jumps over the dog"

text_get(b)
#> [1] "A quick fox jumps over the dog"
```

Sometimes only the new text as a whole is known, not the individual
edits, for example when an editor widget reports its full contents.
[`text_update()`](https://rundel.github.io/creditor/reference/text.md)
compares the new string with the current text and applies just the
insertions and deletions that turn one into the other. Deleting the old
text and inserting the new string would look the same on this replica,
but it makes the edit a rewrite of every character, which no longer
lines up with what other replicas changed. Below, `a` changes the time
and `b` the day, and the merge keeps both. Had `a` deleted and
reinserted the whole text instead, the merge would give
`"Meeting at 12:30 on TuesdayWedn"`.

``` r
a = loro_doc(peer_id = 1) |>
  text_insert(1, "Meeting at noon on Tuesday")
b = replica(a, peer_id = 2)

text_update(a, "Meeting at 12:30 on Tuesday")
text_update(b, "Meeting at noon on Wednesday")

sync(a, b) |>
  text_get()
#> [1] "Meeting at 12:30 on Wednesday"
```

### Rich text

Text can carry marks: a key and a value attached to a range of
characters. Marks are how formatting, links, and comments are
represented.
[`text_delta()`](https://rundel.github.io/creditor/reference/richtext.md)
returns the text as a sequence of runs, each with the marks that apply
to it. It prints as Markdown by default;
[`print()`](https://rdrr.io/r/base/print.html) with `format = "html"`,
`"ansi"`, or `"list"` shows it another way, and the
`creditor.delta_format` option changes the default.

``` r
doc = loro_doc(peer_id = 1) |>
  text_insert(1, "Read the docs today") |>
  text_mark(1, 4, bold = TRUE) |>
  text_mark(10, 13, link = "https://loro.dev")

text_delta(doc)
#> <loro_delta>
#> **Read** the [docs](https://loro.dev) today

str(text_delta(doc))
#> List of 4
#>  $ :List of 2
#>   ..$ insert    : chr "Read"
#>   ..$ attributes:List of 1
#>   .. ..$ bold: logi TRUE
#>  $ :List of 1
#>   ..$ insert: chr " the "
#>  $ :List of 2
#>   ..$ insert    : chr "docs"
#>   ..$ attributes:List of 1
#>   .. ..$ link: chr "https://loro.dev"
#>  $ :List of 1
#>   ..$ insert: chr " today"
```

[`text_markdown()`](https://rundel.github.io/creditor/reference/richtext.md)
returns that Markdown as a string, and
[`text_html()`](https://rundel.github.io/creditor/reference/richtext.md)
renders the marks as HTML instead. In the console,
[`text_ansi()`](https://rundel.github.io/creditor/reference/richtext.md)
shows the text with the marks as terminal styles (bold, italic, colored
links, and so on); a rendered page like this one has no terminal styles,
so it is not shown here.

``` r
text_markdown(doc)
#> [1] "**Read** the [docs](https://loro.dev) today"

text_html(doc)
#> [1] "<strong>Read</strong> the <a href=\"https://loro.dev\">docs</a> today"
```

The HTML can be written straight into a page, such as this one:

``` r
cat(text_html(doc))
```

**Read** the [docs](https://loro.dev) today

Marks merge with concurrent edits. If one replica makes a phrase bold
while another types inside it, the new characters are bold too.

``` r
a = loro_doc(peer_id = 1) |>
  text_insert(1, "Hello world")
b = replica(a, peer_id = 2)

text_mark(a, 1, 5, bold = TRUE)
text_insert(b, 3, "XX")

sync(a, b) |>
  text_markdown()
#> [1] "**HeXXllo** world"
```

Each mark key has an expand rule that decides whether text typed at the
edge of a marked range joins the mark. Bold expands at its end, so
typing after a bold word continues in bold. A link does not, so typing
after a link produces plain text. Keys other than the built-in ones
(`bold`, `italic`, `underline`, `link`, `highlight`, `comment`, and
`code`) must be declared first with
[`doc_config_text_style()`](https://rundel.github.io/creditor/reference/richtext.md).

``` r
loro_doc(peer_id = 1) |>
  doc_config_text_style(author = "none") |>
  text_insert(1, "Reviewed") |>
  text_mark(1, 8, author = "cr") |>
  text_html()
#> [1] "<span data-author=\"cr\">Reviewed</span>"
```

Markdown has no way to write a mark like `author`, so
[`text_markdown()`](https://rundel.github.io/creditor/reference/richtext.md)
leaves it out, while
[`text_html()`](https://rundel.github.io/creditor/reference/richtext.md)
keeps it as a `data-` attribute.

## Map

A map holds values under string keys, like a named list. Values can be
scalars, vectors, or nested lists. This example uses a handle to a root
map named `settings`.

``` r
doc = loro_doc(peer_id = 1)
settings = doc_map(doc, "settings") |>
  map_set(theme = "dark", font_size = 12L, recent = c("a.qmd", "b.qmd"))

map_keys(settings)
#> [1] "font_size" "recent"    "theme"

map_get(settings, "theme")
#> [1] "dark"

settings |>
  container_value() |>
  str()
#> List of 3
#>  $ font_size: int 12
#>  $ recent   :List of 2
#>   ..$ : chr "a.qmd"
#>   ..$ : chr "b.qmd"
#>  $ theme    : chr "dark"
```

A map handle also answers to the functions that work on a named list, so
the same reads and writes can be spelled the base R way.

``` r
settings$theme
#> [1] "dark"

settings$theme = "light"
names(settings)
#> [1] "font_size" "recent"    "theme"

str(as.list(settings))
#> List of 3
#>  $ font_size: int 12
#>  $ recent   :List of 2
#>   ..$ : chr "a.qmd"
#>   ..$ : chr "b.qmd"
#>  $ theme    : chr "light"
```

A vector is stored as a list and comes back as one, so `recent` above
reads back as a list of two strings.

Concurrent writes to different keys are both kept. Concurrent writes to
the same key cannot both be kept, so one of them wins, and it is the
same one on every replica.

``` r
a = loro_doc(peer_id = 1) |>
  map_set(theme = "light")
b = replica(a, peer_id = 2)

map_set(a, theme = "dark", font_size = 12L)
map_set(b, theme = "sepia", line_numbers = TRUE)

sync(a, b) |>
  doc_map() |>
  as.list() |>
  str()
#> List of 3
#>  $ font_size   : int 12
#>  $ line_numbers: logi TRUE
#>  $ theme       : chr "sepia"

identical(doc_value(a), doc_value(b))
#> [1] TRUE
```

A stored value is replaced as a unit. If two replicas each change one
element of the `recent` vector, one whole vector wins. When the parts of
a value should merge independently, store a child container instead; see
[Nesting containers](#nesting-containers).

## List

A list is an ordered sequence of values, addressed by 1-based position.

``` r
loro_doc(peer_id = 1) |>
  list_push("milk", "eggs") |>
  list_insert(1, "bread") |>
  list_delete(2) |>
  doc_list() |>
  as.list() |>
  str()
#> List of 2
#>  $ : chr "bread"
#>  $ : chr "eggs"
```

Concurrent insertions are all kept, even at the same position. Their
relative order is decided the same way on every replica.

``` r
a = loro_doc(peer_id = 1) |>
  list_push("milk")
b = replica(a, peer_id = 2)

list_push(a, "eggs")
list_push(b, "bread")

sync(a, b) |>
  doc_list() |>
  as.list() |>
  str()
#> List of 3
#>  $ : chr "milk"
#>  $ : chr "eggs"
#>  $ : chr "bread"
```

A plain list has no way to move or replace an element. You can imitate a
move by deleting an element and inserting it elsewhere, but if two
replicas do that to the same element, each insertion is kept and the
element is duplicated.

``` r
a = loro_doc(peer_id = 1) |>
  list_push("write", "test", "ship")
b = replica(a, peer_id = 2)

move_by_copy = function(list, from, to) {
  value = list_get(list, from)
  list |>
    list_delete(from) |>
    list_insert(to, value)
}
move_by_copy(a, 3, 1)
move_by_copy(b, 3, 2)

sync(a, b) |>
  doc_list() |>
  as.list() |>
  str()
#> List of 4
#>  $ : chr "ship"
#>  $ : chr "write"
#>  $ : chr "ship"
#>  $ : chr "test"
```

“ship” now appears twice. The movable list exists to solve this.

## Movable list

A movable list supports everything a list does, plus two operations that
merge cleanly:
[`list_move()`](https://rundel.github.io/creditor/reference/list.md)
moves an element, and
[`list_set()`](https://rundel.github.io/creditor/reference/list.md)
replaces one in place. It uses the same `list_*` functions as a plain
list. A document on its own stands for its plain list, so a movable list
always needs a handle, from
[`doc_movable_list()`](https://rundel.github.io/creditor/reference/containers.md)
or a parent container.

``` r
doc = loro_doc(peer_id = 1)
doc_movable_list(doc, "tasks") |>
  list_push("write", "test", "ship") |>
  list_move(3, 1) |>
  list_set(2, "write docs") |>
  as.list() |>
  str()
#> List of 3
#>  $ : chr "ship"
#>  $ : chr "write docs"
#>  $ : chr "test"
```

Repeating the concurrent move from the previous section with a movable
list leaves one copy of the element. The two replicas disagreed about
where it should go, so one destination wins.

``` r
a = loro_doc(peer_id = 1)
tasks = doc_movable_list(a, "tasks") |>
  list_push("write", "test", "ship")
b = replica(a, peer_id = 2)

list_move(tasks, 3, 1)
doc_movable_list(b, "tasks") |>
  list_move(3, 2)

sync(a, b)
tasks |>
  as.list() |>
  str()
#> List of 3
#>  $ : chr "write"
#>  $ : chr "ship"
#>  $ : chr "test"
```

A move and an edit to the same element also combine: if one replica
reorders a task while another rewrites it, the result is the rewritten
task in its new position.

``` r
a = loro_doc(peer_id = 1)
tasks = doc_movable_list(a, "tasks") |>
  list_push("write", "test", "ship")
b = replica(a, peer_id = 2)

list_move(tasks, 1, 3)
doc_movable_list(b, "tasks") |>
  list_set(1, "write the vignette")

sync(a, b)
tasks |>
  as.list() |>
  str()
#> List of 3
#>  $ : chr "test"
#>  $ : chr "ship"
#>  $ : chr "write the vignette"
```

Use a movable list whenever users can reorder or replace elements. A
plain list is enough for append-only data such as a log.

## Counter

A counter holds a number that is changed by adding to it. Concurrent
increments are all applied, so the total is the sum of what every
replica added.

``` r
a = loro_doc(peer_id = 1)
b = replica(a, peer_id = 2)

counter_increment(a, 3)
b |>
  counter_increment(4) |>
  counter_increment(-1)

sync(a, b) |>
  counter_get()
#> [1] 6
```

Compare that with keeping the count as a number in a map. Each replica
reads the current value, adds to it, and writes the result back. After a
merge only one of those writes survives, and the other replica’s votes
are lost.

``` r
a = loro_doc(peer_id = 1) |>
  map_set(votes = 0)
b = replica(a, peer_id = 2)

add_votes = function(doc, n) {
  map_set(doc, votes = map_get(doc, "votes") + n)
}
add_votes(a, 3)
add_votes(b, 4)

sync(a, b) |>
  map_get("votes")
#> [1] 4
```

## Tree

A tree is a hierarchy of nodes, such as an outline, a folder structure,
or a set of nested comments.
[`tree_create()`](https://rundel.github.io/creditor/reference/tree.md)
adds a node and returns its id. Each node has a metadata map that holds
its contents, reached with
[`tree_meta()`](https://rundel.github.io/creditor/reference/tree.md) and
edited with the `map_*` functions.

``` r
doc = loro_doc(peer_id = 1)
outline = doc_tree(doc)

add_section = function(tree, title, parent = NULL) {
  tree_create(tree, parent = parent, meta = list(title = title))
}

intro = add_section(outline, "Introduction")
methods = add_section(outline, "Methods")
data = add_section(outline, "Data", parent = methods)
model = add_section(outline, "Model", parent = methods)

tree_nodes(outline)
#> # A tibble: 4 × 3
#>   id    parent index
#>   <chr> <chr>  <int>
#> 1 0@1   <NA>       1
#> 2 2@1   <NA>       2
#> 3 4@1   2@1        1
#> 4 6@1   2@1        2
```

[`tree_nodes()`](https://rundel.github.io/creditor/reference/tree.md)
gives a flat table of the structure. A small recursive function prints
it as an outline.

``` r
show_outline = function(tree, parent = NULL, depth = 0) {
  for (node in tree_children(tree, parent)) {
    title = map_get(tree_meta(tree, node), "title")
    cat(strrep("  ", depth), "- ", title, "\n", sep = "")
    show_outline(tree, node, depth + 1)
  }
}
show_outline(outline)
#> - Introduction
#> - Methods
#>   - Data
#>   - Model
```

Moving a node carries its whole subtree with it.

``` r
outline |>
  tree_move(methods, parent = intro) |>
  show_outline()
#> - Introduction
#>   - Methods
#>     - Data
#>     - Model
```

The hard case for a tree is two replicas making moves that are each
valid alone but contradictory together. Here one replica moves “Methods”
under “Introduction” while the other moves “Introduction” under
“Methods”. Applying both would create a cycle with no path to the top
level. Loro keeps one of the moves and drops the other, so the result is
always a valid tree and no node is lost.

``` r
a = loro_doc(peer_id = 1)
intro = add_section(a, "Introduction")
methods = add_section(a, "Methods")
b = replica(a, peer_id = 2)

tree_move(a, methods, parent = intro)
tree_move(b, intro, parent = methods)

sync(a, b) |>
  show_outline()
#> - Introduction
#>   - Methods

identical(tree_nodes(a), tree_nodes(b))
#> [1] TRUE
```

Edits to a node’s metadata are independent of moves, because the
metadata is an ordinary map. Here one replica moves “Methods” back to
the top level while the other retitles it, and both changes apply.

``` r
tree_move(a, methods)
tree_meta(b, methods) |>
  map_set(title = "Approach")

sync(a, b) |>
  show_outline()
#> - Introduction
#> - Approach
```

## Nesting containers

Maps, lists, movable lists, and tree metadata can hold child containers
as well as plain values. This is what lets a real document be more than
one flat structure, and it controls how finely concurrent edits merge.

[`loro_text()`](https://rundel.github.io/creditor/reference/loro_text.md),
[`loro_map()`](https://rundel.github.io/creditor/reference/loro_text.md),
[`loro_list()`](https://rundel.github.io/creditor/reference/loro_text.md),
[`loro_movable_list()`](https://rundel.github.io/creditor/reference/loro_text.md),
[`loro_counter()`](https://rundel.github.io/creditor/reference/loro_text.md),
and
[`loro_tree()`](https://rundel.github.io/creditor/reference/loro_text.md)
create a new container, optionally with initial contents, that can be
stored anywhere a plain value can. New containers nest the way R lists
do.

``` r
doc = loro_doc(peer_id = 1)
note = doc_map(doc, "note") |>
  map_set(
    title = "Trip planning",
    body = loro_text("Flights are booked."),
    todo = loro_movable_list(loro_map(label = "Book hotel", done = FALSE)),
    likes = loro_counter(1)
  )

doc |>
  doc_value() |>
  str()
#> List of 1
#>  $ note:List of 4
#>   ..$ body : chr "Flights are booked."
#>   ..$ likes: num 1
#>   ..$ title: chr "Trip planning"
#>   ..$ todo :List of 1
#>   .. ..$ :List of 2
#>   .. .. ..$ done : logi FALSE
#>   .. .. ..$ label: chr "Book hotel"
```

Once stored, a handle refers to the container in the document, so it can
keep being used for edits.

``` r
body = loro_text("Flights")
note$body = body
body |>
  text_push(" and trains are booked.") |>
  text_get()
#> [1] "Flights and trains are booked."
```

Reading a child container back gives a handle, so nested structures can
be navigated step by step or reached directly by path.

``` r
class(map_get(note, "body"))[1]
#> [1] "creditor::loro_text"

note |>
  map_get("body") |>
  text_get()
#> [1] "Flights and trains are booked."

doc_get(doc, "note", "todo", 1, "label")
#> [1] "Book hotel"
```

The difference between a plain value and a child container is the unit
of merging. Below, the same data is stored twice: once as a plain nested
list under one key, and once as a child map. Two replicas then change
different fields.

``` r
a = loro_doc(peer_id = 1) |>
  map_set(
    plain = list(label = "Book hotel", done = FALSE),
    child = loro_map(label = "Book hotel", done = FALSE)
  )
b = replica(a, peer_id = 2)

map_set(a, plain = list(label = "Book hotel", done = TRUE))
doc_map(a)$child |>
  map_set(done = TRUE)

map_set(b, plain = list(label = "Book a hotel in Lisbon", done = FALSE))
doc_map(b)$child |>
  map_set(label = "Book a hotel in Lisbon")

sync(a, b) |>
  doc_map() |>
  as.list() |>
  str()
#> List of 2
#>  $ child:List of 2
#>   ..$ done : logi TRUE
#>   ..$ label: chr "Book a hotel in Lisbon"
#>  $ plain:List of 2
#>   ..$ done : logi FALSE
#>   ..$ label: chr "Book a hotel in Lisbon"
```

In the child map both changes survive: the item is relabeled and marked
done. In the plain value one replica’s whole list replaced the other’s,
so one of the two changes is gone.

### Creating children on first use

When replicas create a child container lazily, the first time it is
needed, two of them may each create one under the same key before they
have synced. Storing a new container with
[`map_set()`](https://rundel.github.io/creditor/reference/map.md) makes
those two different containers, and after a merge only one is visible.
[`map_ensure_container()`](https://rundel.github.io/creditor/reference/map.md)
creates the child in a way that makes both replicas end up with the same
container, so the edits from both are kept.

``` r
a = loro_doc(peer_id = 1)
b = loro_doc(peer_id = 2)

a |>
  map_ensure_container("body", "text") |>
  text_insert(1, "From A. ")
b |>
  map_ensure_container("body", "text") |>
  text_insert(1, "From B. ")

sync(a, b) |>
  map_get("body") |>
  text_get()
#> [1] "From A. From B. "
```

## Choosing a container

| Container    | Holds                         | Concurrent edits                                             | Typical use                          |
|--------------|-------------------------------|--------------------------------------------------------------|--------------------------------------|
| Text         | A string, with optional marks | Insertions and deletions all apply                           | Prose, code, any edited string       |
| Map          | Values under string keys      | Different keys both apply; the same key has one winner       | Records, settings, fields of an item |
| List         | An ordered sequence           | All insertions are kept                                      | Logs and append-only collections     |
| Movable list | An ordered sequence           | As a list, plus moves and replacements that do not duplicate | Anything users reorder               |
| Counter      | A number                      | Increments add up                                            | Votes, tallies, usage counts         |
| Tree         | A hierarchy of nodes          | Moves never create cycles or lose nodes                      | Outlines, folders, nested comments   |

Two rules of thumb cover most decisions. First, if a value is edited
piece by piece, give it a container of its own instead of storing it as
a plain value. Second, pick the container whose merge behavior is the
one you would want if two people made the change at the same moment.
