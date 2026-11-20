# Create a Loro document

A `loro_doc` is a handle to a Loro CRDT document held in Rust. It has
reference semantics: functions that edit a document modify it in place
and return it invisibly, so copies made with `=` refer to the same
document. Use
[`doc_fork()`](https://rundel.github.io/creditor/reference/doc.md) for
an independent replica.

## Usage

``` r
loro_doc(peer_id = NULL)
```

## Arguments

- peer_id:

  Optional peer id identifying this replica: a whole number or a string
  of digits (peer ids are unsigned 64-bit integers, so large ids must be
  given as strings). A random id is used when `NULL`.

## Value

A `loro_doc` object.

## Examples

``` r
doc = loro_doc()
text_insert(doc, 1, "Hello")
text_get(doc)
#> [1] "Hello"

# the same, through a handle to the root text container
text = doc_text(doc)
text_push(text, " world")
text_get(text)
#> [1] "Hello world"
```
