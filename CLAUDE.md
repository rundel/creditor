# creditor

R package that wraps the [`loro`](https://github.com/loro-dev/loro) Rust
crate to expose Loro CRDT documents to R. Exploratory. The build and
binding layout mirrors the sibling [`q2r`](https://rundel.github.io/q2r)
package.

## Architecture

### Rust

- [src/rust/src/lib.rs](https://rundel.github.io/creditor/src/rust/src/lib.rs)
  exposes thin `#[extendr]` functions named `loro_*_impl`, tagged
  `/// @noRd` so they are not R-exported. Fallible calls return
  `extendr_api::Result`, which surfaces as an R error.
- Two pointer types cross the boundary: `ExternalPtr<LoroDoc>` for
  documents and `ExternalPtr<loro::Container>` for every container
  handle. Using the `Container` enum (rather than one pointer type per
  container) keeps a single handle type; each function unwraps the
  variant it needs via `as_text` / `as_map` / `as_movable_list` /
  `as_counter` / `as_tree` and errors on a mismatch. `LoroList` and
  `LoroMovableList` share method names but no trait, so the shared
  `loro_list_*` functions dispatch over both with the `with_list!`
  macro. New containers are created detached (`detached_container`, the
  one place that lists the creatable kinds) and attached with
  `insert_container` / `set_container` (`loro_*_attach_impl`), which
  copies the detached contents, nested detached children included, into
  the document. Loro records the attached copy on the detached object;
  `loro_container_resolve_impl` swaps a handle’s `Container` for it in
  place, so every R reference to the external pointer follows the
  container into the document.
- A handle is returned to R by `container_ref` as `list(kind, ptr)` with
  class `creditor_container_ref`. Functions that can return either a
  plain value or a child container (`loro_map_get_impl`,
  `loro_list_get_impl`) go through `value_or_container_to_r`; the class
  is what lets R tell the two apart, since plain values never carry one.
  Text, map, list, movable list, counter, and tree are supported; an
  unknown container type falls back to its deep value on read.
- [src/rust/src/container_value.rs](https://rundel.github.io/creditor/src/rust/src/container_value.rs)
  produces container and document values (`container_to_r`, `doc_to_r`)
  by walking the handles, not by converting `get_deep_value()`. A
  `LoroValue` no longer records which container each part came from, so
  a tree node’s 0-based `index` could not be told apart from a map entry
  named `index`; the walker knows the type and emits tree nodes with
  1-based `index` and `NA` root parents. Items are collected from
  `for_each` before any child is read, so no Loro iteration is open
  while another container is accessed. The `deep` flag switches child
  containers between expanded contents and id strings. Diffs and
  subscription events still use `get_deep_value()` for inserted child
  containers (they are built while Loro is emitting an event, where
  reading other containers is not safe), so a tree nested inside a diff
  insert keeps Loro’s raw form.
- [src/rust/src/value_to_r.rs](https://rundel.github.io/creditor/src/rust/src/value_to_r.rs)
  converts a `LoroValue` into nested R lists (map keys sorted for stable
  output; `I64` becomes an integer when it fits and is not
  `NA_integer_`, else a double).
- [src/rust/src/r_to_value.rs](https://rundel.github.io/creditor/src/rust/src/r_to_value.rs)
  is the inverse, for values stored with `map_set` / `list_insert`:
  `NULL` and `NA` become null, length-one atomic vectors become scalars,
  other unnamed vectors and lists become lists, named ones become maps,
  raw becomes binary, and anything with a class attribute is rejected.
  Zero-length vectors are handled before any slice is taken, because
  building a slice from an empty R vector’s data pointer panics (and
  aborts R) in debug builds.
- [src/rust/src/delta.rs](https://rundel.github.io/creditor/src/rust/src/delta.rs)
  converts between `Vec<TextDelta>` and the R delta shape (a list of
  ops, each a named list with one of `retain` / `insert` / `delete` plus
  optional `attributes`). Delta counts are Unicode code points, like
  every other text index.
- Rich text: mark keys must be present in the document’s
  `StyleConfigMap` or `mark` fails with “Style configuration missing”.
  `loro_doc_config_text_style_impl` always starts from
  `StyleConfigMap::default_rich_text_config()` (bold, italic, underline,
  link, highlight, comment, code) and overlays the caller’s keys,
  because `config_text_style` replaces the whole map and there is no
  getter to merge with. Keys containing `:` are rejected up front since
  `StyleConfigMap::insert` panics on them.
- Cursors cross as `Cursor::encode()` bytes and are resolved with
  `LoroDoc::get_cursor_pos`. `LoroText::get_cursor` does not reject an
  out-of-range position (it silently returns an end cursor), so the
  range check lives in R. List cursors (`loro_list_cursor_impl`) work on
  both list types, but Loro cannot resolve a cursor on a movable-list
  element once that element has been moved (`get_cursor_pos` fails with
  “Cannot find relative position”); this is documented and pinned by a
  test.
- [src/rust/src/history.rs](https://rundel.github.io/creditor/src/rust/src/history.rs)
  converts a `DiffBatch` (text, list, and map diffs; child containers by
  deep value; other types as `unsupported`) and the change log
  (`travel_change_ancestors` from the oplog frontiers, sorted by lamport
  then peer) to R. The diff’s type field is emitted as `type_` because
  `type` is a Rust keyword inside `list!`; R renames it. Versions for
  history cross as `Frontiers::encode()` bytes; a change’s frontiers is
  the id of its last op.
- [`doc_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
  reports `state_frontiers()` (what the document is showing), which
  differs from the oplog frontiers while detached. A detached document
  is read-only (detached editing is not enabled).
- [src/rust/src/events.rs](https://rundel.github.io/creditor/src/rust/src/events.rs)
  implements subscriptions as queues, not direct callbacks. Loro’s
  subscriber closure converts each event to an R object and pushes it
  onto an `EventQueue`; R later drains the queue with
  `loro_subscription_take_impl` and calls the user’s function. This
  keeps R code (which can error, or re-enter Loro) from ever running
  inside a Loro commit or import. `EventQueue` has
  `unsafe impl Send + Sync` because Loro requires it of subscribers
  while `Robj` is neither; this is sound only because every Loro call
  happens on R’s main thread. Do not introduce threads without
  revisiting it.
- The ephemeral store is an
  `ExternalPtr<loro::awareness::EphemeralStore>`, independent of any
  document. Its two subscription kinds reuse `QueuedSubscription`.
  Inside `loro_ephemeral_get_impl` the pointer is first re-borrowed as
  `&EphemeralStore`, because calling `.get()` on the `ExternalPtr`
  resolves to extendr’s `GetSexp::get` instead of Loro’s method; watch
  for this with any Loro method named `get`.
- Detached editing (`set_detached_editing`) is a per-object runtime
  switch. While it is on, Loro assigns a fresh random peer id at every
  checkout and keeps it after re-attaching; edits made at an old version
  become a concurrent branch that merges on `doc_checkout(doc)`.
- Text positions can be converted between units with
  `LoroText::convert_pos` (`unicode`, `utf16`, and `utf8` map to
  `PosType::Unicode` / `Utf16` / `Bytes`). The R side keeps positions
  1-based in every unit. A mid-character offset converts to the start of
  that character; only out-of-range offsets give `NA`.
- An explicit commit timestamp is stored even when timestamp recording
  is off, and Loro forces timestamps to be non-decreasing, so later
  commits without one inherit the latest stored value.
- `subscribe_first_commit_from_peer` fires only for local commits (once
  per peer id this document commits under), not for imported peers.
- Commit origins (`set_next_commit_origin`) are local labels: they reach
  subscribers as `event$origin` and are matched by prefix against an
  undo manager’s excluded origins, but are not stored in history. Loro
  labels the commits made by undo and redo with origin `"undo"`.
- Undo is a plain `ExternalPtr<UndoManager>`; `undo` / `redo` return
  whether anything changed. Loro clears the undo and redo stacks on
  checkout.
- Sync extras in `lib.rs`: `loro_doc_export_impl` also handles
  `shallow_snapshot` (encoded frontiers in `since`); imports return an
  `ImportStatus` converted by `status_to_r` to column-wise `success` /
  `pending` ranges; JSON updates are serialized with `serde_json` (a
  direct dependency for that reason); JSONPath needs the `jsonpath`
  feature of the `loro` crate. `loro_doc_apply_diff_impl` computes the
  `DiffBatch` in a source document and applies it in the same call, so
  no diff object has to cross into R (the R list from
  [`doc_diff()`](https://rundel.github.io/creditor/reference/history.md)
  is lossy: child containers appear by value).
- More Loro behaviors worked around: unparseable JSON passed to
  `import_json_updates` surfaces an unrelated “no active undo group”
  error, so the JSON is converted to a `JsonSchema` first and a clear
  error raised; `LoroList::pop` returns a child container as a bare id,
  so `loro_list_pop_impl` reads the deep value before deleting;
  `ensure_mergeable_*` on a key that already holds a mergeable container
  of another type silently creates a second container under the same
  key, so `loro_map_ensure_container_impl` checks the existing type
  first.
- `to_r_error` strips the `Position: <source path>` suffix and the
  `at <path>.rs:LINE:COL` suffix (Unix or Windows path) Loro appends to
  some error messages.
- Robustness rules learned from reviewing against Loro’s own tests (each
  has a test):
  - Strings: extendr exposes an R string’s bytes as `&str` unchecked,
    and Loro panics on invalid UTF-8, poisoning the document’s mutex
    (later calls fail, and R can abort at exit). Every string therefore
    goes through `as_utf8()` in R (`check_string`) or `utf8_strings()`
    in Rust (`r_to_value.rs`, also used for names and delta inserts):
    translate with `enc2utf8`, then validate. Never read a user string
    with `as_str()` / `as_ref()` directly.
  - Recursion: `r_to_value` and the container walker cap nesting at 1000
    levels and return an error. Unbounded recursion overflows the C
    stack, which R reports as an uncatchable segfault; if it happens
    inside Loro while a lock is held the process can also hang at exit.
  - Bounds: positions and ranges for text and lists are checked in R
    (`check_insert_pos`, `check_element_pos`, `check_positions`,
    `check_range` in `R/utils.R`), and tree indexes in Rust
    (`check_tree_index`), so errors name the 1-based value the caller
    passed. Loro’s own messages are 0-based and sometimes report the end
    of a range, and Loro skips the bounds check for zero-length ranges.
    Range arithmetic is done in doubles to avoid integer overflow.
  - Versions:
    [`doc_version()`](https://rundel.github.io/creditor/reference/doc_sync.md)
    returns class `loro_version` and
    [`doc_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
    / `doc_changes()$frontiers` class `loro_frontiers` (raw vectors
    underneath). The encodings overlap, so Loro decodes one as the other
    without error and silently uses a different version; `check_version`
    / `check_frontiers` prevent that. Anywhere frontiers are expected,
    `check_frontiers(x, arg, doc)` also accepts a change number (in
    [`doc_changes()`](https://rundel.github.io/creditor/reference/history.md)
    order) or a commit message, resolved against that document’s history
    (`source`’s for `doc_apply_diff`) and returned as frontiers; callers
    must use its return value. A message that matches no change or
    several is an error. Indexing
    [`doc_changes()`](https://rundel.github.io/creditor/reference/history.md)
    (`changes$frontiers[[1]]`, `changes[1, ]`) is deliberately not the
    documented way to name a version.
  - `revert_to` and `apply_diff` write into the open transaction without
    committing; the bindings commit afterwards so the change reaches
    subscribers, undo, and live sync.
  - Map diffs report `updated` (keys set, possibly to `NULL`) separately
    from `deleted` (keys removed).
  - Trees: a node inside a deleted subtree is not live. Loro would let
    it be moved (reviving the subtree) or deleted; `to_live_node`
    rejects both.
  - [`undo_group()`](https://rundel.github.io/creditor/reference/undo.md)
    commits pending edits before the group starts and before it ends
    (the manager object keeps the document pointer for this); otherwise
    edits inside the group merge into whatever is committed next.
  - JSON:
    [`doc_export_json()`](https://rundel.github.io/creditor/reference/doc_sync.md)
    refuses a document whose JSON contains the marker Loro 1.18 writes
    for a
    [`map_ensure_container()`](https://rundel.github.io/creditor/reference/map.md)
    child (`"value":[0,76,77,1,...]`), because importing it corrupts the
    receiving replica. This is an upstream bug; recheck it when bumping
    `loro`.
- Trees: node ids cross as `TreeID`’s display form (`"counter@peer"`),
  parsed back with `TreeID::try_from`; a root-level parent is `NULL`
  going in and `NA` coming out. Three Loro behaviors are worked around
  or documented. `LoroTree::children` returns `None` for a leaf as well
  as for a missing node, so `loro_tree_children_impl` checks existence
  itself. Loro allows a deleted node as the parent of a create or move
  (the node lands in the deleted part of the tree), which
  `to_live_parent` rejects. Undoing or reverting a node deletion
  recreates the subtree under new node ids.
- Positions in Rust are 0-based (text positions are Unicode code point
  indices via `LoroText::insert` / `delete` / `len_unicode`). Peer ids
  are `u64` and cross as decimal strings. Versions cross as
  `VersionVector::encode()` bytes.
- [src/rust/document.rs](https://rundel.github.io/creditor/src/rust/document.rs)
  is the `document` binary that regenerates
  [R/extendr-wrappers.R](https://rundel.github.io/creditor/R/extendr-wrappers.R)
  on every build. New functions must be listed in the `extendr_module!`
  block.

### R

- [R/doc.R](https://rundel.github.io/creditor/R/doc.R) defines the
  exported S7 class `loro_doc` (a `@ptr` slot holding the external
  pointer, so documents have reference semantics, and a `@state`
  environment for R-side state shared by every reference to the
  document) and the `doc_*` functions: identity, fork, commit, deep
  value, path queries (`doc_get`, which walks the handles in R one step
  per argument with 1-based list positions, and `doc_jsonpath`, whose
  expression keeps JSONPath’s 0-based positions), and sync (`doc_export`
  / `doc_export_updates` / `doc_export_shallow`, one function per export
  mode so no argument depends on another, plus `doc_import` /
  `doc_version`, JSON updates, `blob_metadata`). `doc_import` /
  `doc_import_json` return the document so they pipe; the status of the
  most recent import is stored in `doc@state$import_status` and read
  with
  [`doc_import_status()`](https://rundel.github.io/creditor/reference/doc_sync.md).
  A plain attribute on the returned object would not work, because
  callers who do not capture the result would never see it.
- [R/container.R](https://rundel.github.io/creditor/R/container.R)
  defines the S7 handle classes: abstract `loro_container` (unexported)
  with children `loro_text`, `loro_map`, `loro_list`, `loro_counter`,
  and `loro_tree`, plus `loro_movable_list` as a child of `loro_list`
  (so every `list_*` function accepts it, while `list_move` / `list_set`
  require it). The child classes are exported because their constructors
  create new detached containers with initial contents
  (`loro_list("a", "b")`, `loro_text("hi")`); internally a handle is
  wrapped with the `.ptr` argument instead. A new container is stored
  wherever a value is (`map_store` / `list_store` / `list_set`, via
  `attachable`). `container_ptr` (and `handle_ptr` for functions that do
  not accept a document) resolves a detached handle that has since been
  attached, so every container function must get its pointer through one
  of them rather than reading `@ptr` directly. Users get handles from
  [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md)
  /
  [`doc_map()`](https://rundel.github.io/creditor/reference/containers.md)
  /
  [`doc_list()`](https://rundel.github.io/creditor/reference/containers.md)
  /
  [`doc_movable_list()`](https://rundel.github.io/creditor/reference/containers.md)
  /
  [`doc_counter()`](https://rundel.github.io/creditor/reference/containers.md)
  /
  [`doc_tree()`](https://rundel.github.io/creditor/reference/containers.md)
  (root containers) or from a parent container; `container_from_ref`
  turns a Rust `creditor_container_ref` into the matching class and
  passes plain values through. Also holds
  [`container_value()`](https://rundel.github.io/creditor/reference/containers.md),
  [`container_id()`](https://rundel.github.io/creditor/reference/containers.md),
  and the shared print method.
- [R/text.R](https://rundel.github.io/creditor/R/text.R),
  [R/map.R](https://rundel.github.io/creditor/R/map.R),
  [R/list.R](https://rundel.github.io/creditor/R/list.R),
  [R/counter.R](https://rundel.github.io/creditor/R/counter.R), and
  [R/tree.R](https://rundel.github.io/creditor/R/tree.R) define the
  `text_*`, `map_*`, `list_*`, `counter_*`, and `tree_*` functions, each
  taking a handle as its first argument. The R API is 1-based; the
  conversion to 0-based happens here. New child containers come from the
  `loro_*()` constructors and are stored like plain values; there are no
  type-name container creators.
- [R/richtext.R](https://rundel.github.io/creditor/R/richtext.R) defines
  `text_mark` / `text_unmark` / `text_delta` / `text_apply_delta` and
  `doc_config_text_style`; `with_style_hint` rewrites Loro’s
  missing-style error (which names the JS API) to point at
  [`doc_config_text_style()`](https://rundel.github.io/creditor/reference/richtext.md).
  [R/cursor.R](https://rundel.github.io/creditor/R/cursor.R) defines
  `text_cursor`, `list_cursor`, and `cursor_pos`; a cursor is a plain
  raw vector, like a version from
  [`doc_version()`](https://rundel.github.io/creditor/reference/doc_sync.md).
- [R/history.R](https://rundel.github.io/creditor/R/history.R) defines
  `doc_frontiers`, `doc_changes` (a tibble with a `frontiers` list
  column), `doc_change`, the counts, `doc_changed_containers`, the
  conversions between frontiers and version vectors,
  `doc_compare_frontiers`, `doc_checkout`, `doc_is_detached`,
  `doc_revert_to`, `doc_diff`, `doc_apply_diff`, and
  `doc_record_timestamps`.
- [R/events.R](https://rundel.github.io/creditor/R/events.R) holds the
  subscription registry (the `the` environment: id to
  `list(ptr, callback)`) and `deliver_events()`. Delivery has three
  properties that tests pin and that must be kept. (1) Every exported
  function that takes a document or undo manager registers
  `on.exit(deliver_events(), add = TRUE)` right after checking its
  argument, so events are delivered whichever Loro call committed them
  (many read-only calls commit implicitly, e.g. `doc_changes`) and also
  when the call errors after committing. A new `doc_*` function must do
  the same; `test-events.R` loops over the committing functions. (2)
  Events are moved from the Rust queues onto one R-side FIFO
  (`the$pending`) and delivered from there; a nested `deliver_events()`
  (a callback that commits) only enqueues and returns, which keeps
  events in order. An event leaves the FIFO just before its callback
  runs, so an interrupted delivery loses nothing. (3) `deliver_events()`
  first asks Rust whether anything is queued at all
  (`loro_events_pending_impl`, a global atomic counter), so a call that
  produced no events costs the same however many subscriptions exist.
  Callback errors become warnings. The registry keeps a subscription
  alive until
  [`unsubscribe()`](https://rundel.github.io/creditor/reference/subscribe.md).
- [R/ephemeral.R](https://rundel.github.io/creditor/R/ephemeral.R)
  defines the `ephemeral_*` functions. Loro’s Rust API does not expire
  entries on a timer (the JS wrapper does), so expiry is only applied
  when
  [`ephemeral_remove_outdated()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  is called. Entries are last-write-wins on a millisecond timestamp, and
  a receiving store drops a write that is not strictly newer, so two
  writes to one key in the same millisecond leave receivers stale; tests
  that sync successive writes to one key must sleep between them
  (`tick()` in `test-ephemeral.R`).
- [R/undo.R](https://rundel.github.io/creditor/R/undo.R) defines
  `doc_undo_manager`, `undo`, `redo`, `can_undo`, `can_redo`, the step
  counts, `undo_group`, pause and resume, and `undo_clear`.
- Tabular results (`doc_changes`, `doc_change`, `tree_nodes`, the import
  status) are tibbles built with
  [`tibble::tibble()`](https://tibble.tidyverse.org/reference/tibble.html),
  never base data frames. A value that has to appear in them must print
  meaningfully: `loro_frontiers` formats as the `counter@peer` ids of
  its operations (`loro_frontiers_ids_impl`) and registers
  [`pillar::obj_sum`](https://pillar.r-lib.org/reference/type_sum.html)
  so list-column cells show the same. If a column needs hiding to make
  output readable, fix its display or drop it instead.
- [R/utils.R](https://rundel.github.io/creditor/R/utils.R) holds the
  argument checks
  ([`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html),
  with `call = rlang::caller_env()`), and `named_values()` /
  `unnamed_values()`, which collect dynamic dots
  ([`rlang::list2()`](https://rlang.r-lib.org/reference/list2.html)). A
  function whose `...` takes user-chosen keys as argument names
  (`map_set`, `ephemeral_set`, `text_mark`, `doc_config_text_style`)
  gives every other argument before `...` a leading dot (`.map`,
  `.store`, `.text` / `.start` / `.end`, `.doc`), because R matches a
  named argument exactly and partially against those formals, so a key
  such as `map`, `st`, or `e` would otherwise be taken as the argument.
  The checks take an `arg` (or `args`) name so their errors name the
  dotted argument.
- Interface conventions, which new functions should follow:
  - Keyed writes take `key = value` pairs in `...` (`map_set`,
    `ephemeral_set`, `text_mark`, `doc_config_text_style`); sequence
    writes take unnamed values in `...`, one element each (`list_push`,
    `list_insert`). Both loop over a single-value Rust call, so a
    rejected value leaves the earlier ones applied. An argument that
    sits beside named dots gets a dot prefix (`.default`).
  - `map_delete` and `ephemeral_delete` take keys in `...` as any number
    of character vectors (`key_dots`); `map_has` and `text_unmark` take
    one character vector; `list_delete` takes a vector of positions and
    deletes contiguous runs from the end backward.
  - Text ranges are `start` / `end`, inclusive, as in
    [`substr()`](https://rdrr.io/r/base/substr.html); an empty range is
    `end = start - 1`. `check_range` converts to the 0-based half-open
    range Rust expects.
  - Durations are in seconds (`ephemeral_store(timeout)`,
    `doc_undo_manager(merge_interval)`) and converted to Loro’s
    milliseconds by `check_seconds`.
  - Every function that takes a container handle also accepts a
    `loro_doc`, which stands for its root container of that type under
    the default name (`text_insert(doc, 1, "a")` is
    `text_insert(doc_text(doc), 1, "a")`). `container_ptr()` does this:
    container functions start with `ptr = container_ptr(x, class, "x")`
    and pass `ptr` to Rust, and still return the argument they were
    given. A document stands for its plain list, so the movable-list
    functions reject one. The base generic methods are for handles only.
  - Handles have methods for base generics, registered with
    [`S7::method()`](https://rconsortium.github.io/S7/reference/method.html):
    `length` (text, map, list), `names` / `$` / `[[` / `$<-` / `[[<-`
    (map), `[[` / `[[<-` (list; assignment needs a movable list),
    `as.character` (text), `as.list` (map, list). The assignment methods
    return the handle, and assigning `NULL` deletes (`map$key = NULL`,
    `list[[pos]] = NULL`), as with an R list; `map_set(map, key = NULL)`
    is the way to store a null. `map$child$key = value` makes R assign
    the child handle back to `child`; `is_same_child` turns that step
    into a no-op; any other handle that is already in a document is
    rejected (`abort_attached`), while a new detached one is stored. The
    empty string is a valid map key that `...` cannot express, so
    `map[[""]] = value` is the way to write it.
- Pipeable editing functions are a primary goal of the API. Every
  exported function is one of three kinds: editors change something and
  return their first argument invisibly (all `text_*` / `map_*` /
  `list_*` / `counter_*` / `tree_*` edits, `doc_import*`, `doc_commit`,
  `doc_checkout`, the `doc_set_*` functions, `undo` / `redo` /
  `undo_group`, the `ephemeral_*` setters); constructors create
  something new and return it (`loro_doc`, the `loro_*` container
  constructors, `doc_fork`, `doc_undo_manager`, the `doc_subscribe*`
  functions, `ephemeral_store`, and `tree_create`, which returns the new
  node id); and accessors and predicates return a value without changing
  anything (`*_get`, `*_length`, `doc_value`, `can_undo`, `doc_is_*`,
  and so on; `list_pop` counts as an accessor that also removes). An
  editor never returns a status: an extra outcome is stored with the
  object and read through an accessor
  ([`doc_import_status()`](https://rundel.github.io/creditor/reference/doc_sync.md)),
  and a no-op that callers may want to catch is reported by a `strict`
  argument that turns it into an error (`undo`, `redo`, `undo_group`).

## Toolchain

- Rust edition 2024, rustc \>= 1.85 (declared in `DESCRIPTION` via
  `SystemRequirements`). Bridge: `extendr-api` 0.9.
- Crates are fetched by cargo at build time (no vendoring; not
  CRAN-targeted). `src/rust/Cargo.lock` is committed.
- `README.md` is generated: edit `README.qmd` and run
  `quarto render README.qmd` with the current package installed, so the
  example output is real. It renders to GitHub markdown with
  `wrap: none` and `smart` off: prose is never hard wrapped, and only
  code comments in the chunks may be wrapped (within 100 characters).
- Rebuild after Rust edits with
  [`devtools::document()`](https://devtools.r-lib.org/reference/document.html);
  set the `DEBUG=1` environment variable for a fast unoptimized build
  (the release profile uses LTO and is slow).
- [tools/config.R](https://rundel.github.io/creditor/tools/config.R) and
  [tools/msrv.R](https://rundel.github.io/creditor/tools/msrv.R) run at
  install time from `configure` to check the toolchain and template
  `src/Makevars{,.win}.in`. They are rextendr-generated; do not restyle
  or remove them.

## Style

- R: use `=` for assignment, `pkg::fn` over imports, minimize
  single-line comments. In examples, the README, and vignettes, chain
  edits with the native pipe (`|>`), one step per line, but only when
  there are at least two steps: a single call on a variable is a plain
  call (`text_push(a, "x")`, not `a |> text_push("x")`).
- Rust: standard rustfmt; no decorative comments.
- Commit messages: one short imperative line, no attribution trailers.
