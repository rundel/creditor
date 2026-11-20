use extendr_api::Result;
use extendr_api::prelude::*;
use loro::cursor::{Cursor, Side};
use loro::{
    Container, ContainerTrait, ExpandType, ExportMode, LoroDoc, LoroList, LoroMap, LoroText,
    StyleConfig, StyleConfigMap, UpdateOptions, ValueOrContainer, VersionVector,
};

mod delta;
mod r_to_value;
mod value_to_r;

use r_to_value::r_to_value;
use value_to_r::value_to_r;

type DocPtr = ExternalPtr<LoroDoc>;
type ContainerPtr = ExternalPtr<Container>;

fn to_r_error<E: std::fmt::Display>(e: E) -> Error {
    let message = e.to_string();
    let message = match message.split_once(" Position: ") {
        Some((head, _)) => head.to_string(),
        None => message,
    };
    Error::Other(message)
}

fn to_index(value: i32, what: &str) -> Result<usize> {
    usize::try_from(value).map_err(|_| Error::Other(format!("{what} must not be negative")))
}

fn kind_of(container: &Container) -> Option<&'static str> {
    match container {
        Container::Text(_) => Some("text"),
        Container::Map(_) => Some("map"),
        Container::List(_) => Some("list"),
        _ => None,
    }
}

fn wrong_kind<T>(expected: &str) -> Result<T> {
    Err(Error::Other(format!("container is not a {expected}")))
}

fn as_text(container: &Container) -> Result<&LoroText> {
    match container {
        Container::Text(text) => Ok(text),
        _ => wrong_kind("text"),
    }
}

fn as_map(container: &Container) -> Result<&LoroMap> {
    match container {
        Container::Map(map) => Ok(map),
        _ => wrong_kind("map"),
    }
}

fn as_list(container: &Container) -> Result<&LoroList> {
    match container {
        Container::List(list) => Ok(list),
        _ => wrong_kind("list"),
    }
}

/// A container handle crosses to R as `list(kind, ptr)` with class
/// `creditor_container_ref`; plain values never carry a class.
fn container_ref(container: Container) -> Result<Robj> {
    let Some(kind) = kind_of(&container) else {
        return Err(Error::Other("unsupported container type".to_string()));
    };
    let mut out: Robj = list!(kind = kind, ptr = ExternalPtr::new(container)).into();
    out.set_class(["creditor_container_ref"])?;
    Ok(out)
}

fn value_or_container_to_r(item: ValueOrContainer) -> Result<Robj> {
    match item {
        ValueOrContainer::Value(value) => Ok(value_to_r(&value)),
        ValueOrContainer::Container(container) if kind_of(&container).is_some() => {
            container_ref(container)
        }
        other => Ok(value_to_r(&other.get_deep_value())),
    }
}

/// Create an empty Loro document.
/// @noRd
#[extendr]
fn loro_doc_new_impl() -> DocPtr {
    ExternalPtr::new(LoroDoc::new())
}

/// Peer id of a document, as a decimal string (it is a u64).
/// @noRd
#[extendr]
fn loro_doc_peer_id_impl(doc: DocPtr) -> String {
    doc.peer_id().to_string()
}

/// Set the peer id of a document from a decimal string.
/// @noRd
#[extendr]
fn loro_doc_set_peer_id_impl(doc: DocPtr, peer_id: &str) -> Result<()> {
    let id: u64 = peer_id.parse().map_err(to_r_error)?;
    doc.set_peer_id(id).map_err(to_r_error)
}

/// Commit the pending transaction.
/// @noRd
#[extendr]
fn loro_doc_commit_impl(doc: DocPtr) {
    doc.commit();
}

/// Fork a document into an independent replica with a new peer id.
/// @noRd
#[extendr]
fn loro_doc_fork_impl(doc: DocPtr) -> DocPtr {
    ExternalPtr::new(doc.fork())
}

/// Encoded version vector of the document's operation log.
/// @noRd
#[extendr]
fn loro_doc_version_impl(doc: DocPtr) -> Raw {
    Raw::from_bytes(&doc.oplog_vv().encode())
}

/// Export a document. `mode` is "snapshot" or "updates"; `from` is an
/// encoded version vector (or `NULL` for all updates).
/// @noRd
#[extendr]
fn loro_doc_export_impl(doc: DocPtr, mode: &str, from: Nullable<Raw>) -> Result<Raw> {
    let bytes = match (mode, from) {
        ("snapshot", _) => doc.export(ExportMode::Snapshot),
        ("updates", Nullable::Null) => doc.export(ExportMode::all_updates()),
        ("updates", Nullable::NotNull(from)) => {
            let vv = VersionVector::decode(from.as_slice()).map_err(to_r_error)?;
            doc.export(ExportMode::updates(&vv))
        }
        _ => return Err(Error::Other(format!("unknown export mode: {mode}"))),
    };
    Ok(Raw::from_bytes(&bytes.map_err(to_r_error)?))
}

/// Import a snapshot or updates into a document.
/// @noRd
#[extendr]
fn loro_doc_import_impl(doc: DocPtr, bytes: Raw) -> Result<()> {
    doc.import(bytes.as_slice()).map_err(to_r_error)?;
    Ok(())
}

/// Deep value of the whole document as nested R lists.
/// @noRd
#[extendr]
fn loro_doc_value_impl(doc: DocPtr) -> Robj {
    value_to_r(&doc.get_deep_value())
}

/// Root container of the given `kind` ("text", "map", or "list").
/// @noRd
#[extendr]
fn loro_doc_container_impl(doc: DocPtr, name: &str, kind: &str) -> Result<Robj> {
    let container = match kind {
        "text" => Container::Text(doc.get_text(name)),
        "map" => Container::Map(doc.get_map(name)),
        "list" => Container::List(doc.get_list(name)),
        _ => return Err(Error::Other(format!("unknown container type: {kind}"))),
    };
    container_ref(container)
}

/// Container id as a string.
/// @noRd
#[extendr]
fn loro_container_id_impl(container: ContainerPtr) -> String {
    container.id().to_string()
}

/// Deep value of a container.
/// @noRd
#[extendr]
fn loro_container_value_impl(container: ContainerPtr) -> Result<Robj> {
    match &*container {
        Container::Text(text) => Ok(text.to_string().into()),
        Container::Map(map) => Ok(value_to_r(&map.get_deep_value())),
        Container::List(list) => Ok(value_to_r(&list.get_deep_value())),
        _ => Err(Error::Other("unsupported container type".to_string())),
    }
}

/// Insert `value` at a 0-based Unicode code point position.
/// @noRd
#[extendr]
fn loro_text_insert_impl(text: ContainerPtr, pos: i32, value: &str) -> Result<()> {
    let pos = to_index(pos, "pos")?;
    as_text(&text)?.insert(pos, value).map_err(to_r_error)
}

/// Delete `len` code points starting at a 0-based position.
/// @noRd
#[extendr]
fn loro_text_delete_impl(text: ContainerPtr, pos: i32, len: i32) -> Result<()> {
    let pos = to_index(pos, "pos")?;
    let len = to_index(len, "len")?;
    as_text(&text)?.delete(pos, len).map_err(to_r_error)
}

/// Length of a text container in Unicode code points.
/// @noRd
#[extendr]
fn loro_text_length_impl(text: ContainerPtr) -> Result<i32> {
    Ok(as_text(&text)?.len_unicode() as i32)
}

/// Set `key` to a plain value.
/// @noRd
#[extendr]
fn loro_map_set_impl(map: ContainerPtr, key: &str, value: Robj) -> Result<()> {
    let value = r_to_value(&value)?;
    as_map(&map)?.insert(key, value).map_err(to_r_error)
}

/// Set `key` to a new child container of the given `kind`.
/// @noRd
#[extendr]
fn loro_map_set_container_impl(map: ContainerPtr, key: &str, kind: &str) -> Result<Robj> {
    let map = as_map(&map)?;
    let child = match kind {
        "text" => Container::Text(
            map.insert_container(key, LoroText::new())
                .map_err(to_r_error)?,
        ),
        "map" => Container::Map(
            map.insert_container(key, LoroMap::new())
                .map_err(to_r_error)?,
        ),
        "list" => Container::List(
            map.insert_container(key, LoroList::new())
                .map_err(to_r_error)?,
        ),
        _ => return Err(Error::Other(format!("unknown container type: {kind}"))),
    };
    container_ref(child)
}

/// Value or child container at `key`; `NULL` when absent.
/// @noRd
#[extendr]
fn loro_map_get_impl(map: ContainerPtr, key: &str) -> Result<Robj> {
    match as_map(&map)?.get(key) {
        Some(item) => value_or_container_to_r(item),
        None => Ok(().into()),
    }
}

/// Remove `key`.
/// @noRd
#[extendr]
fn loro_map_delete_impl(map: ContainerPtr, key: &str) -> Result<()> {
    as_map(&map)?.delete(key).map_err(to_r_error)
}

/// Sorted keys of a map.
/// @noRd
#[extendr]
fn loro_map_keys_impl(map: ContainerPtr) -> Result<Vec<String>> {
    let mut keys: Vec<String> = as_map(&map)?.keys().map(|k| k.to_string()).collect();
    keys.sort();
    Ok(keys)
}

/// Number of entries in a map.
/// @noRd
#[extendr]
fn loro_map_length_impl(map: ContainerPtr) -> Result<i32> {
    Ok(as_map(&map)?.len() as i32)
}

/// Insert a plain value at a 0-based position.
/// @noRd
#[extendr]
fn loro_list_insert_impl(list: ContainerPtr, pos: i32, value: Robj) -> Result<()> {
    let pos = to_index(pos, "pos")?;
    let value = r_to_value(&value)?;
    as_list(&list)?.insert(pos, value).map_err(to_r_error)
}

/// Insert a new child container of the given `kind` at a 0-based position.
/// @noRd
#[extendr]
fn loro_list_insert_container_impl(list: ContainerPtr, pos: i32, kind: &str) -> Result<Robj> {
    let pos = to_index(pos, "pos")?;
    let list = as_list(&list)?;
    let child = match kind {
        "text" => Container::Text(
            list.insert_container(pos, LoroText::new())
                .map_err(to_r_error)?,
        ),
        "map" => Container::Map(
            list.insert_container(pos, LoroMap::new())
                .map_err(to_r_error)?,
        ),
        "list" => Container::List(
            list.insert_container(pos, LoroList::new())
                .map_err(to_r_error)?,
        ),
        _ => return Err(Error::Other(format!("unknown container type: {kind}"))),
    };
    container_ref(child)
}

/// Value or child container at a 0-based position.
/// @noRd
#[extendr]
fn loro_list_get_impl(list: ContainerPtr, pos: i32) -> Result<Robj> {
    let pos = to_index(pos, "pos")?;
    match as_list(&list)?.get(pos) {
        Some(item) => value_or_container_to_r(item),
        None => Err(Error::Other("pos is out of bounds".to_string())),
    }
}

/// Delete `len` elements starting at a 0-based position.
/// @noRd
#[extendr]
fn loro_list_delete_impl(list: ContainerPtr, pos: i32, len: i32) -> Result<()> {
    let pos = to_index(pos, "pos")?;
    let len = to_index(len, "len")?;
    as_list(&list)?.delete(pos, len).map_err(to_r_error)
}

/// Number of elements in a list.
/// @noRd
#[extendr]
fn loro_list_length_impl(list: ContainerPtr) -> Result<i32> {
    Ok(as_list(&list)?.len() as i32)
}

fn to_expand(expand: &str) -> Result<ExpandType> {
    match expand {
        "after" => Ok(ExpandType::After),
        "before" => Ok(ExpandType::Before),
        "both" => Ok(ExpandType::Both),
        "none" => Ok(ExpandType::None),
        _ => Err(Error::Other(format!("unknown expand type: {expand}"))),
    }
}

/// Set the document's text style configuration to Loro's built-in styles
/// overlaid with `keys` / `expands` (parallel vectors); `default` applies
/// to any other key (`NULL` for none).
/// @noRd
#[extendr]
fn loro_doc_config_text_style_impl(
    doc: DocPtr,
    keys: Vec<String>,
    expands: Vec<String>,
    default: Nullable<String>,
) -> Result<()> {
    let mut styles = StyleConfigMap::default_rich_text_config();
    for (key, expand) in keys.iter().zip(expands.iter()) {
        if key.contains(':') {
            return Err(Error::Other("style keys must not contain ':'".to_string()));
        }
        styles.insert(
            key.as_str().into(),
            StyleConfig {
                expand: to_expand(expand)?,
            },
        );
    }
    let default = match default {
        Nullable::NotNull(expand) => Some(StyleConfig {
            expand: to_expand(&expand)?,
        }),
        Nullable::Null => None,
    };
    doc.config_text_style(styles);
    doc.config_default_text_style(default);
    Ok(())
}

/// Resolve an encoded cursor to its current 0-based position.
/// @noRd
#[extendr]
fn loro_doc_cursor_pos_impl(doc: DocPtr, cursor: Raw) -> Result<i32> {
    let cursor = Cursor::decode(cursor.as_slice()).map_err(to_r_error)?;
    let result = doc.get_cursor_pos(&cursor).map_err(to_r_error)?;
    Ok(result.current.pos as i32)
}

/// Encoded cursor anchored at a 0-based position. `side` is -1, 0, or 1.
/// @noRd
#[extendr]
fn loro_text_cursor_impl(text: ContainerPtr, pos: i32, side: i32) -> Result<Raw> {
    let pos = to_index(pos, "pos")?;
    let Some(side) = Side::from_i32(side) else {
        return Err(Error::Other("side must be -1, 0, or 1".to_string()));
    };
    match as_text(&text)?.get_cursor(pos, side) {
        Some(cursor) => Ok(Raw::from_bytes(&cursor.encode())),
        None => Err(Error::Other(
            "cannot create a cursor at this position".to_string(),
        )),
    }
}

/// Mark the 0-based code point range `[start, end)` with `key = value`.
/// @noRd
#[extendr]
fn loro_text_mark_impl(
    text: ContainerPtr,
    start: i32,
    end: i32,
    key: &str,
    value: Robj,
) -> Result<()> {
    let range = to_index(start, "start")?..to_index(end, "end")?;
    let value = r_to_value(&value)?;
    as_text(&text)?.mark(range, key, value).map_err(to_r_error)
}

/// Remove the mark `key` from the 0-based code point range `[start, end)`.
/// @noRd
#[extendr]
fn loro_text_unmark_impl(text: ContainerPtr, start: i32, end: i32, key: &str) -> Result<()> {
    let range = to_index(start, "start")?..to_index(end, "end")?;
    as_text(&text)?.unmark(range, key).map_err(to_r_error)
}

/// Rich text contents as a list of insert ops.
/// @noRd
#[extendr]
fn loro_text_delta_impl(text: ContainerPtr) -> Result<Robj> {
    Ok(delta::delta_to_r(as_text(&text)?.to_delta()))
}

/// Apply a list of retain / insert / delete ops.
/// @noRd
#[extendr]
fn loro_text_apply_delta_impl(text: ContainerPtr, delta: Robj) -> Result<()> {
    let delta = delta::delta_from_r(&delta)?;
    as_text(&text)?.apply_delta(&delta).map_err(to_r_error)
}

/// Change the text to `value` by applying a minimal diff.
/// @noRd
#[extendr]
fn loro_text_update_impl(text: ContainerPtr, value: &str) -> Result<()> {
    as_text(&text)?
        .update(value, UpdateOptions::default())
        .map_err(to_r_error)
}

extendr_module! {
    mod creditor;
    fn loro_doc_new_impl;
    fn loro_doc_peer_id_impl;
    fn loro_doc_set_peer_id_impl;
    fn loro_doc_commit_impl;
    fn loro_doc_fork_impl;
    fn loro_doc_version_impl;
    fn loro_doc_export_impl;
    fn loro_doc_import_impl;
    fn loro_doc_value_impl;
    fn loro_doc_container_impl;
    fn loro_container_id_impl;
    fn loro_container_value_impl;
    fn loro_text_insert_impl;
    fn loro_text_delete_impl;
    fn loro_text_length_impl;
    fn loro_doc_config_text_style_impl;
    fn loro_doc_cursor_pos_impl;
    fn loro_text_cursor_impl;
    fn loro_text_mark_impl;
    fn loro_text_unmark_impl;
    fn loro_text_delta_impl;
    fn loro_text_apply_delta_impl;
    fn loro_text_update_impl;
    fn loro_map_set_impl;
    fn loro_map_set_container_impl;
    fn loro_map_get_impl;
    fn loro_map_delete_impl;
    fn loro_map_keys_impl;
    fn loro_map_length_impl;
    fn loro_list_insert_impl;
    fn loro_list_insert_container_impl;
    fn loro_list_get_impl;
    fn loro_list_delete_impl;
    fn loro_list_length_impl;
}
