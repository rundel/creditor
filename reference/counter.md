# Counters

A counter holds a number that replicas change by adding to it. When
replicas increment concurrently, every increment is kept and the results
add up. A number stored with
[`map_set()`](https://rundel.github.io/creditor/reference/map.md) would
instead keep only one replica's value.

- `counter_increment()` adds `by` to the counter; a negative value
  subtracts.

- `counter_get()` returns the current value.

## Usage

``` r
counter_increment(counter, by = 1)

counter_get(counter)
```

## Arguments

- counter:

  A counter handle, from
  [`doc_counter()`](https://rundel.github.io/creditor/reference/containers.md)
  or a parent container.

- by:

  A number to add.

## Value

`counter_increment()` returns `counter` invisibly and `counter_get()` a
number.

## Examples

``` r
doc = loro_doc()
votes = doc_counter(doc, "votes")
counter_increment(votes)
counter_increment(votes, 2)
counter_get(votes)
#> [1] 3
```
