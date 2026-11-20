# creditor

Exploratory R bindings to [Loro](https://loro.dev), a Rust library of conflict-free replicated data types (CRDTs). Replicas of a document edit independently, exchange updates as raw vectors, and converge to the same contents. Text (including rich text marks and cursors), map, and list containers are supported, and they can be nested.

## Installation

Building from source needs a Rust toolchain (cargo and rustc >= 1.85).

```r
# install.packages("pak")
pak::pak("rundel/creditor")
```

## Example

Two replicas edit the same text concurrently and then merge.

```r
library(creditor)

a = loro_doc()
text_insert(doc_text(a), 1, "Hello")

b = loro_doc()
doc_import(b, doc_export(a))

text_insert(doc_text(a), 6, " world")
text_insert(doc_text(b), 1, ">> ")

doc_import(b, doc_export(a, "updates", from = doc_version(b)))
doc_import(a, doc_export(b, "updates", from = doc_version(a)))

text_get(doc_text(a))
#> [1] ">> Hello world"
text_get(doc_text(b))
#> [1] ">> Hello world"
```

Containers nest: a map or list can hold plain values or child containers, each of which merges independently.

```r
doc = loro_doc()
note = doc_map(doc, "note")
map_set(note, "title", "Groceries")

items = map_set_container(note, "items", "list")
list_push(items, "milk")
list_push(items, "eggs")

body = map_set_container(note, "body", "text")
text_insert(body, 1, "Buy before Friday")

str(doc_value(doc))
#> List of 1
#>  $ note:List of 3
#>   ..$ body : chr "Buy before Friday"
#>   ..$ items:List of 2
#>   .. ..$ : chr "milk"
#>   .. ..$ : chr "eggs"
#>   ..$ title: chr "Groceries"
```

Text can carry marks, and a cursor keeps pointing at the same character as the text changes.

```r
doc = loro_doc()
text = doc_text(doc)
text_insert(text, 1, "Hello world")
text_mark(text, 1, 5, "bold")
cursor = text_cursor(text, 7)

text_update(text, "Hello brave new world")
str(text_delta(text))
#> List of 2
#>  $ :List of 2
#>   ..$ insert    : chr "Hello"
#>   ..$ attributes:List of 1
#>   .. ..$ bold: logi TRUE
#>  $ :List of 1
#>   ..$ insert: chr " brave new world"
cursor_pos(doc, cursor)
#> [1] 17
```
