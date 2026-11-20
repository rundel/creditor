# Version objects

Loro names versions in two ways, and creditor gives each its own class
so that one cannot be passed where the other is expected:

- a version vector (class `loro_version`), from
  [`doc_version()`](https://rundel.github.io/creditor/reference/doc_sync.md),
  used to ask for the updates a replica is missing;

- frontiers (class `loro_frontiers`), from
  [`doc_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
  and
  [`doc_changes()`](https://rundel.github.io/creditor/reference/history.md),
  used to name a point in history.

Both are raw vectors underneath, so
[`unclass()`](https://rdrr.io/r/base/class.html) gives bytes that can be
stored or sent elsewhere. `as_version()` and `as_frontiers()` put the
class back on such bytes. They do not convert between the two kinds; use
[`doc_frontiers_to_version()`](https://rundel.github.io/creditor/reference/history.md)
and
[`doc_version_to_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
for that.

## Usage

``` r
as_version(x)

as_frontiers(x)
```

## Arguments

- x:

  A raw vector.

## Value

`as_version()` returns a `loro_version` and `as_frontiers()` a
`loro_frontiers`.

## Examples

``` r
doc = loro_doc()
text_insert(doc, 1, "a")
frontiers = doc_frontiers(doc)
frontiers
#> <loro_frontiers> 01 a7 d4 88 b6 cb fd af 8c c0 01 00

saved = unclass(frontiers)
identical(as_frontiers(saved), frontiers)
#> [1] TRUE
```
