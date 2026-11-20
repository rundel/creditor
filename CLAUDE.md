# creditor

R package that wraps the [`loro`](https://github.com/loro-dev/loro) Rust crate to expose Loro CRDT documents to R. Exploratory. The build and binding layout mirrors the sibling [`q2r`](../q2r) package.

## Architecture

### Rust

- [src/rust/src/lib.rs](src/rust/src/lib.rs) exposes thin `#[extendr]` functions named `loro_*_impl`, tagged `/// @noRd` so they are not R-exported. Fallible calls return `extendr_api::Result`, which surfaces as an R error.
- Two pointer types cross the boundary: `ExternalPtr<LoroDoc>` for documents and `ExternalPtr<loro::Container>` for every container handle. Using the `Container` enum (rather than one pointer type per container) keeps a single handle type; each function unwraps the variant it needs via `as_text` / `as_map` / `as_movable_list` / `as_counter` and errors on a mismatch. `LoroList` and `LoroMovableList` share method names but no trait, so the shared `loro_list_*` functions dispatch over both with the `with_list!` macro. Child containers are created through the `new_child!` macro, which is the one place that lists the creatable kinds.
- A handle is returned to R by `container_ref` as `list(kind, ptr)` with class `creditor_container_ref`. Functions that can return either a plain value or a child container (`loro_map_get_impl`, `loro_list_get_impl`) go through `value_or_container_to_r`; the class is what lets R tell the two apart, since plain values never carry one. Text, map, list, movable list, and counter are supported; other container types (tree, unknown) fall back to their deep value on read.
- [src/rust/src/value_to_r.rs](src/rust/src/value_to_r.rs) converts a `LoroValue` into nested R lists (map keys sorted for stable output; `I64` becomes an integer when it fits and is not `NA_integer_`, else a double).
- [src/rust/src/r_to_value.rs](src/rust/src/r_to_value.rs) is the inverse, for values stored with `map_set` / `list_insert`: `NULL` and `NA` become null, length-one atomic vectors become scalars, other unnamed vectors and lists become lists, named ones become maps, raw becomes binary, and anything with a class attribute is rejected. Zero-length vectors are handled before any slice is taken, because building a slice from an empty R vector's data pointer panics (and aborts R) in debug builds.
- [src/rust/src/delta.rs](src/rust/src/delta.rs) converts between `Vec<TextDelta>` and the R delta shape (a list of ops, each a named list with one of `retain` / `insert` / `delete` plus optional `attributes`). Delta counts are Unicode code points, like every other text index.
- Rich text: mark keys must be present in the document's `StyleConfigMap` or `mark` fails with "Style configuration missing". `loro_doc_config_text_style_impl` always starts from `StyleConfigMap::default_rich_text_config()` (bold, italic, underline, link, highlight, comment, code) and overlays the caller's keys, because `config_text_style` replaces the whole map and there is no getter to merge with. Keys containing `:` are rejected up front since `StyleConfigMap::insert` panics on them.
- Cursors cross as `Cursor::encode()` bytes and are resolved with `LoroDoc::get_cursor_pos`. `LoroText::get_cursor` does not reject an out-of-range position (it silently returns an end cursor), so the range check lives in R.
- [src/rust/src/history.rs](src/rust/src/history.rs) converts a `DiffBatch` (text, list, and map diffs; child containers by deep value; other types as `unsupported`) and the change log (`travel_change_ancestors` from the oplog frontiers, sorted by lamport then peer) to R. The diff's type field is emitted as `type_` because `type` is a Rust keyword inside `list!`; R renames it. Versions for history cross as `Frontiers::encode()` bytes; a change's frontiers is the id of its last op.
- `doc_frontiers()` reports `state_frontiers()` (what the document is showing), which differs from the oplog frontiers while detached. A detached document is read-only (detached editing is not enabled).
- [src/rust/src/events.rs](src/rust/src/events.rs) implements subscriptions as queues, not direct callbacks. Loro's subscriber closure converts each event to an R object and pushes it onto an `EventQueue`; R later drains the queue with `loro_subscription_take_impl` and calls the user's function. This keeps R code (which can error, or re-enter Loro) from ever running inside a Loro commit or import. `EventQueue` has `unsafe impl Send + Sync` because Loro requires it of subscribers while `Robj` is neither; this is sound only because every Loro call happens on R's main thread. Do not introduce threads without revisiting it.
- The ephemeral store is an `ExternalPtr<loro::awareness::EphemeralStore>`, independent of any document. Its two subscription kinds reuse `QueuedSubscription`. Inside `loro_ephemeral_get_impl` the pointer is first re-borrowed as `&EphemeralStore`, because calling `.get()` on the `ExternalPtr` resolves to extendr's `GetSexp::get` instead of Loro's method; watch for this with any Loro method named `get`.
- Undo is a plain `ExternalPtr<UndoManager>`; `undo` / `redo` return whether anything changed. Loro clears the undo and redo stacks on checkout.
- `to_r_error` strips the ` Position: <source path>` suffix Loro appends to some error messages.
- Positions in Rust are 0-based (text positions are Unicode code point indices via `LoroText::insert` / `delete` / `len_unicode`). Peer ids are `u64` and cross as decimal strings. Versions cross as `VersionVector::encode()` bytes.
- [src/rust/document.rs](src/rust/document.rs) is the `document` binary that regenerates [R/extendr-wrappers.R](R/extendr-wrappers.R) on every build. New functions must be listed in the `extendr_module!` block.

### R

- [R/doc.R](R/doc.R) defines the exported S7 class `loro_doc` (a `@ptr` slot holding the external pointer, so documents have reference semantics) and the `doc_*` functions: identity, fork, commit, deep value, and sync (`doc_export` / `doc_import` / `doc_version`).
- [R/container.R](R/container.R) defines the unexported S7 handle classes: abstract `loro_container` with children `loro_text`, `loro_map`, `loro_list`, and `loro_counter`, plus `loro_movable_list` as a child of `loro_list` (so every `list_*` function accepts it, while `list_move` / `list_set` / `list_set_container` require it). Users get handles from `doc_text()` / `doc_map()` / `doc_list()` / `doc_movable_list()` / `doc_counter()` (root containers) or from a parent container; `container_from_ref` turns a Rust `creditor_container_ref` into the matching class and passes plain values through. Also holds `container_value()`, `container_id()`, and the shared print method.
- [R/text.R](R/text.R), [R/map.R](R/map.R), [R/list.R](R/list.R), and [R/counter.R](R/counter.R) define the `text_*`, `map_*`, `list_*`, and `counter_*` functions, each taking a handle as its first argument. The R API is 1-based; the conversion to 0-based happens here. Child containers are created empty by type name (`map_set_container`, `list_insert_container`, `list_push_container`) and returned as handles.
- [R/richtext.R](R/richtext.R) defines `text_mark` / `text_unmark` / `text_delta` / `text_apply_delta` and `doc_config_text_style`; `with_style_hint` rewrites Loro's missing-style error (which names the JS API) to point at `doc_config_text_style()`. [R/cursor.R](R/cursor.R) defines `text_cursor` and `cursor_pos`; a cursor is a plain raw vector, like a version from `doc_version()`.
- [R/history.R](R/history.R) defines `doc_frontiers`, `doc_changes` (a data frame with a `frontiers` list column), `doc_checkout`, `doc_is_detached`, `doc_revert_to`, `doc_diff`, and `doc_record_timestamps`.
- [R/events.R](R/events.R) holds the subscription registry (the `the` environment: id to `list(ptr, callback)`) and `deliver_events()`, which drains every registered queue and invokes callbacks, turning callback errors into warnings. Every exported function that can commit or import must call `deliver_events()` before returning (currently `doc_commit`, `doc_import`, `doc_export`, `doc_fork`, `doc_checkout`, `doc_revert_to`, `doc_diff`, `undo`, `redo`, `undo_group`, and the mutating `ephemeral_*` functions); a function that misses it only delays delivery until the next one. The registry keeps a subscription alive until `unsubscribe()`.
- [R/ephemeral.R](R/ephemeral.R) defines the `ephemeral_*` functions. Loro's Rust API does not expire entries on a timer (the JS wrapper does), so expiry is only applied when `ephemeral_remove_outdated()` is called. Entries are last-write-wins on a millisecond timestamp, and a receiving store drops a write that is not strictly newer, so two writes to one key in the same millisecond leave receivers stale; tests that sync successive writes to one key must sleep between them (`tick()` in `test-ephemeral.R`).
- [R/undo.R](R/undo.R) defines `doc_undo_manager`, `undo`, `redo`, `can_undo`, `can_redo`, and `undo_group`.
- [R/utils.R](R/utils.R) holds the argument checks (`cli::cli_abort()`).
- Mutating functions return their first argument invisibly, except the `*_container` creators, which return the new handle.

## Toolchain

- Rust edition 2024, rustc >= 1.85 (declared in `DESCRIPTION` via `SystemRequirements`). Bridge: `extendr-api` 0.9.
- Crates are fetched by cargo at build time (no vendoring; not CRAN-targeted). `src/rust/Cargo.lock` is committed.
- Rebuild after Rust edits with `devtools::document()`; set the `DEBUG=1` environment variable for a fast unoptimized build (the release profile uses LTO and is slow).
- [tools/config.R](tools/config.R) and [tools/msrv.R](tools/msrv.R) run at install time from `configure` to check the toolchain and template `src/Makevars{,.win}.in`. They are rextendr-generated; do not restyle or remove them.

## Style

- R: use `=` for assignment, `pkg::fn` over imports, minimize single-line comments.
- Rust: standard rustfmt; no decorative comments.
- Commit messages: one short imperative line, no attribution trailers.
