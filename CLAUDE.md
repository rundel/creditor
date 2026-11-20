# creditor

R package that wraps the [`loro`](https://github.com/loro-dev/loro) Rust crate to expose Loro CRDT documents to R. Exploratory. The build and binding layout mirrors the sibling [`q2r`](../q2r) package.

## Architecture

### Rust

- [src/rust/src/lib.rs](src/rust/src/lib.rs) exposes thin `#[extendr]` functions named `loro_*_impl`, tagged `/// @noRd` so they are not R-exported. Fallible calls return `extendr_api::Result`, which surfaces as an R error.
- Two pointer types cross the boundary: `ExternalPtr<LoroDoc>` for documents and `ExternalPtr<loro::Container>` for every container handle. Using the `Container` enum (rather than one pointer type per container) keeps a single handle type; each `loro_text_*` / `loro_map_*` / `loro_list_*` function unwraps the variant it needs via `as_text` / `as_map` / `as_list` and errors on a mismatch.
- A handle is returned to R by `container_ref` as `list(kind, ptr)` with class `creditor_container_ref`. Functions that can return either a plain value or a child container (`loro_map_get_impl`, `loro_list_get_impl`) go through `value_or_container_to_r`; the class is what lets R tell the two apart, since plain values never carry one. Only text, map, and list are supported; other container types (movable list, tree, counter) fall back to their deep value on read.
- [src/rust/src/value_to_r.rs](src/rust/src/value_to_r.rs) converts a `LoroValue` into nested R lists (map keys sorted for stable output; `I64` becomes an integer when it fits and is not `NA_integer_`, else a double).
- [src/rust/src/r_to_value.rs](src/rust/src/r_to_value.rs) is the inverse, for values stored with `map_set` / `list_insert`: `NULL` and `NA` become null, length-one atomic vectors become scalars, other unnamed vectors and lists become lists, named ones become maps, raw becomes binary, and anything with a class attribute is rejected. Zero-length vectors are handled before any slice is taken, because building a slice from an empty R vector's data pointer panics (and aborts R) in debug builds.
- [src/rust/src/delta.rs](src/rust/src/delta.rs) converts between `Vec<TextDelta>` and the R delta shape (a list of ops, each a named list with one of `retain` / `insert` / `delete` plus optional `attributes`). Delta counts are Unicode code points, like every other text index.
- Rich text: mark keys must be present in the document's `StyleConfigMap` or `mark` fails with "Style configuration missing". `loro_doc_config_text_style_impl` always starts from `StyleConfigMap::default_rich_text_config()` (bold, italic, underline, link, highlight, comment, code) and overlays the caller's keys, because `config_text_style` replaces the whole map and there is no getter to merge with. Keys containing `:` are rejected up front since `StyleConfigMap::insert` panics on them.
- Cursors cross as `Cursor::encode()` bytes and are resolved with `LoroDoc::get_cursor_pos`. `LoroText::get_cursor` does not reject an out-of-range position (it silently returns an end cursor), so the range check lives in R.
- `to_r_error` strips the ` Position: <source path>` suffix Loro appends to some error messages.
- Positions in Rust are 0-based (text positions are Unicode code point indices via `LoroText::insert` / `delete` / `len_unicode`). Peer ids are `u64` and cross as decimal strings. Versions cross as `VersionVector::encode()` bytes.
- [src/rust/document.rs](src/rust/document.rs) is the `document` binary that regenerates [R/extendr-wrappers.R](R/extendr-wrappers.R) on every build. New functions must be listed in the `extendr_module!` block.

### R

- [R/doc.R](R/doc.R) defines the exported S7 class `loro_doc` (a `@ptr` slot holding the external pointer, so documents have reference semantics) and the `doc_*` functions: identity, fork, commit, deep value, and sync (`doc_export` / `doc_import` / `doc_version`).
- [R/container.R](R/container.R) defines the unexported S7 handle classes: abstract `loro_container` with children `loro_text`, `loro_map`, and `loro_list`. Users get handles from `doc_text()` / `doc_map()` / `doc_list()` (root containers) or from a parent container; `container_from_ref` turns a Rust `creditor_container_ref` into the matching class and passes plain values through. Also holds `container_value()`, `container_id()`, and the shared print method.
- [R/text.R](R/text.R), [R/map.R](R/map.R), and [R/list.R](R/list.R) define the `text_*`, `map_*`, and `list_*` functions, each taking a handle as its first argument. The R API is 1-based; the conversion to 0-based happens here. Child containers are created empty by type name (`map_set_container`, `list_insert_container`, `list_push_container`) and returned as handles.
- [R/richtext.R](R/richtext.R) defines `text_mark` / `text_unmark` / `text_delta` / `text_apply_delta` and `doc_config_text_style`; `with_style_hint` rewrites Loro's missing-style error (which names the JS API) to point at `doc_config_text_style()`. [R/cursor.R](R/cursor.R) defines `text_cursor` and `cursor_pos`; a cursor is a plain raw vector, like a version from `doc_version()`.
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
