use extendr_api::Result;
use extendr_api::prelude::*;
use std::sync::Arc;

use loro::awareness::EphemeralStore;
use loro::cursor::{Cursor, PosType, Side};
use loro::{
    Container, ContainerTrait, ExpandType, ExportMode, Frontiers, ID, ImportStatus, JsonSchema,
    LoroCounter, LoroDoc, LoroList, LoroMap, LoroMovableList, LoroText, LoroTree, StyleConfig,
    StyleConfigMap, TreeID, TreeParentId, UndoManager, UpdateOptions, ValueOrContainer,
    VersionRange, VersionVector,
};

mod container_value;
mod delta;
mod events;
mod history;
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
    Error::Other(strip_source_location(message))
}

/// Remove a trailing ` at <path>.rs:LINE:COL` that Loro appends to some
/// messages, keeping any closing parenthesis after it. The path may be a
/// Unix or a Windows path.
fn strip_source_location(message: String) -> String {
    for (start, _) in message.rmatch_indices(" at ") {
        let tail = &message[start + 4..];
        let (location, closing) = match tail.strip_suffix(')') {
            Some(location) => (location, ")"),
            None => (tail, ""),
        };
        if is_source_location(location) {
            return format!("{}{}", &message[..start], closing);
        }
    }
    message
}

fn is_source_location(location: &str) -> bool {
    let mut parts = location.rsplitn(3, ':');
    let digits =
        |s: Option<&str>| s.is_some_and(|s| !s.is_empty() && s.bytes().all(|b| b.is_ascii_digit()));
    let col = parts.next();
    let line = parts.next();
    digits(col) && digits(line) && parts.next().is_some_and(|path| path.ends_with(".rs"))
}

fn to_index(value: i32, what: &str) -> Result<usize> {
    usize::try_from(value).map_err(|_| Error::Other(format!("{what} must not be negative")))
}

fn kind_of(container: &Container) -> Option<&'static str> {
    match container {
        Container::Text(_) => Some("text"),
        Container::Map(_) => Some("map"),
        Container::List(_) => Some("list"),
        Container::MovableList(_) => Some("movable_list"),
        Container::Counter(_) => Some("counter"),
        Container::Tree(_) => Some("tree"),
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

fn as_movable_list(container: &Container) -> Result<&LoroMovableList> {
    match container {
        Container::MovableList(list) => Ok(list),
        _ => wrong_kind("movable list"),
    }
}

fn as_tree(container: &Container) -> Result<&LoroTree> {
    match container {
        Container::Tree(tree) => Ok(tree),
        _ => wrong_kind("tree"),
    }
}

fn to_node(node: &str) -> Result<TreeID> {
    TreeID::try_from(node).map_err(|_| Error::Other(format!("not a valid node id: {node}")))
}

fn to_parent(parent: Nullable<String>) -> Result<TreeParentId> {
    match parent {
        Nullable::Null => Ok(TreeParentId::Root),
        Nullable::NotNull(parent) => Ok(TreeParentId::Node(to_node(&parent)?)),
    }
}

/// Loro accepts a deleted node as the parent of a create or move, which
/// puts the node in the deleted part of the tree; reject that here.
fn to_live_parent(tree: &LoroTree, parent: Nullable<String>) -> Result<TreeParentId> {
    let parent = to_parent(parent)?;
    if let TreeParentId::Node(node) = parent {
        if !tree.contains(node) || tree.is_node_deleted(&node).unwrap_or(true) {
            return Err(Error::Other(
                "parent node does not exist or has been deleted".to_string(),
            ));
        }
    }
    Ok(parent)
}

fn as_counter(container: &Container) -> Result<&LoroCounter> {
    match container {
        Container::Counter(counter) => Ok(counter),
        _ => wrong_kind("counter"),
    }
}

/// Run `$body` with `$list` bound to a `LoroList` or `LoroMovableList`,
/// which share method names but no trait.
macro_rules! with_list {
    ($container:expr, |$list:ident| $body:expr) => {
        match &*$container {
            Container::List($list) => $body,
            Container::MovableList($list) => $body,
            _ => return wrong_kind("list"),
        }
    };
}

/// A new container of `kind` that belongs to no document.
fn detached_container(kind: &str) -> Result<Container> {
    Ok(match kind {
        "text" => Container::Text(LoroText::new()),
        "map" => Container::Map(LoroMap::new()),
        "list" => Container::List(LoroList::new()),
        "movable_list" => Container::MovableList(LoroMovableList::new()),
        "counter" => Container::Counter(LoroCounter::new()),
        "tree" => Container::Tree(LoroTree::new()),
        _ => return Err(Error::Other(format!("unknown container type: {kind}"))),
    })
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
        other => container_value::item_to_r(&other, true),
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

/// Commit the pending transaction, optionally with a message and a
/// timestamp (seconds since the epoch) kept in history, and an origin
/// label passed to subscribers.
/// @noRd
#[extendr]
fn loro_doc_commit_impl(
    doc: DocPtr,
    message: Nullable<String>,
    origin: Nullable<String>,
    timestamp: Nullable<f64>,
) {
    if let Nullable::NotNull(message) = message {
        doc.set_next_commit_message(&message);
    }
    if let Nullable::NotNull(origin) = origin {
        doc.set_next_commit_origin(&origin);
    }
    if let Nullable::NotNull(timestamp) = timestamp {
        doc.set_next_commit_timestamp(timestamp as i64);
    }
    doc.commit();
}

/// Record wall-clock timestamps on new changes.
/// @noRd
#[extendr]
fn loro_doc_record_timestamps_impl(doc: DocPtr, record: bool) {
    doc.set_record_timestamp(record);
}

fn to_frontiers(bytes: &Raw) -> Result<Frontiers> {
    Frontiers::decode(bytes.as_slice())
        .map_err(|_| Error::Other("not a valid frontiers value".to_string()))
}

/// The operation ids in encoded frontiers, as `counter@peer` strings.
/// @noRd
#[extendr]
fn loro_frontiers_ids_impl(frontiers: Raw) -> Result<Vec<String>> {
    Ok(to_frontiers(&frontiers)?
        .iter()
        .map(|id| id.to_string())
        .collect())
}

/// Encoded frontiers of the version the document state is at.
/// @noRd
#[extendr]
fn loro_doc_frontiers_impl(doc: DocPtr) -> Raw {
    Raw::from_bytes(&doc.state_frontiers().encode())
}

/// Check out a version (encoded frontiers), or the latest when `NULL`.
/// @noRd
#[extendr]
fn loro_doc_checkout_impl(doc: DocPtr, frontiers: Nullable<Raw>) -> Result<()> {
    match frontiers {
        Nullable::Null => doc.try_checkout_to_latest().map_err(to_r_error),
        Nullable::NotNull(frontiers) => {
            doc.checkout(&to_frontiers(&frontiers)?).map_err(to_r_error)
        }
    }
}

/// Whether the document state is detached from the latest version.
/// @noRd
#[extendr]
fn loro_doc_is_detached_impl(doc: DocPtr) -> bool {
    doc.is_detached()
}

/// Generate new changes that restore the state at `frontiers`.
/// @noRd
#[extendr]
fn loro_doc_revert_to_impl(doc: DocPtr, frontiers: Raw) -> Result<()> {
    doc.revert_to(&to_frontiers(&frontiers)?)
        .map_err(to_r_error)?;
    // Loro leaves the generated changes in the open transaction.
    doc.commit();
    Ok(())
}

/// Diff between two versions as a named list keyed by container id.
/// @noRd
#[extendr]
fn loro_doc_diff_impl(doc: DocPtr, from: Raw, to: Raw) -> Result<Robj> {
    let batch = doc
        .diff(&to_frontiers(&from)?, &to_frontiers(&to)?)
        .map_err(to_r_error)?;
    Ok(history::diff_batch_to_r(&batch))
}

/// Metadata for every change in the document's history, column-wise.
/// @noRd
#[extendr]
fn loro_doc_changes_impl(doc: DocPtr) -> Result<Robj> {
    history::changes_to_r(&doc)
}

/// Fork a document into an independent replica with a new peer id,
/// optionally at an earlier version given as encoded frontiers.
/// @noRd
#[extendr]
fn loro_doc_fork_impl(doc: DocPtr, at: Nullable<Raw>) -> Result<DocPtr> {
    match at {
        Nullable::Null => Ok(ExternalPtr::new(doc.fork())),
        Nullable::NotNull(at) => {
            let frontiers = to_frontiers(&at)?;
            Ok(ExternalPtr::new(
                doc.fork_at(&frontiers).map_err(to_r_error)?,
            ))
        }
    }
}

/// Encoded version vector of the document's operation log.
/// @noRd
#[extendr]
fn loro_doc_version_impl(doc: DocPtr) -> Raw {
    Raw::from_bytes(&doc.oplog_vv().encode())
}

/// Export a document. `mode` is "snapshot", "updates" (since the encoded
/// version vector `from`, or everything when `NULL`), or
/// "shallow_snapshot" (dropping history before the encoded frontiers
/// `since`, or before the latest version when `NULL`).
/// @noRd
#[extendr]
fn loro_doc_export_impl(
    doc: DocPtr,
    mode: &str,
    from: Nullable<Raw>,
    since: Nullable<Raw>,
) -> Result<Raw> {
    let bytes = match (mode, from) {
        ("snapshot", _) => doc.export(ExportMode::Snapshot),
        ("updates", Nullable::Null) => doc.export(ExportMode::all_updates()),
        ("updates", Nullable::NotNull(from)) => {
            let vv = VersionVector::decode(from.as_slice()).map_err(to_r_error)?;
            doc.export(ExportMode::updates(&vv))
        }
        ("shallow_snapshot", _) => {
            let frontiers = match since {
                Nullable::NotNull(since) => to_frontiers(&since)?,
                Nullable::Null => doc.oplog_frontiers(),
            };
            doc.export(ExportMode::shallow_snapshot(&frontiers))
        }
        _ => return Err(Error::Other(format!("unknown export mode: {mode}"))),
    };
    Ok(Raw::from_bytes(&bytes.map_err(to_r_error)?))
}

fn range_to_r(range: Option<&VersionRange>) -> Robj {
    let mut spans: Vec<(u64, i32, i32)> = match range {
        Some(range) => range
            .iter()
            .map(|(peer, (start, end))| (*peer, *start, *end))
            .collect(),
        None => Vec::new(),
    };
    spans.sort();
    let peer: Vec<String> = spans.iter().map(|s| s.0.to_string()).collect();
    let start: Vec<i32> = spans.iter().map(|s| s.1).collect();
    let end: Vec<i32> = spans.iter().map(|s| s.2).collect();
    list!(peer = peer, start = start, end = end).into()
}

/// Operation ranges an import applied (`success`) and those it is holding
/// until their missing dependencies arrive (`pending`), column-wise.
fn status_to_r(status: &ImportStatus) -> Robj {
    list!(
        success = range_to_r(Some(&status.success)),
        pending = range_to_r(status.pending.as_ref())
    )
    .into()
}

/// Import a snapshot or updates into a document.
/// @noRd
#[extendr]
fn loro_doc_import_impl(doc: DocPtr, bytes: Raw) -> Result<Robj> {
    let status = doc.import(bytes.as_slice()).map_err(to_r_error)?;
    Ok(status_to_r(&status))
}

/// Import several snapshots or updates in one step.
/// @noRd
#[extendr]
fn loro_doc_import_batch_impl(doc: DocPtr, blobs: List) -> Result<Robj> {
    let blobs = blobs
        .values()
        .map(|blob| match blob.as_raw_slice() {
            Some(bytes) => Ok(bytes.to_vec()),
            None if blob.rtype() == Rtype::Raw => Ok(Vec::new()),
            None => Err(Error::Other(
                "every element must be a raw vector".to_string(),
            )),
        })
        .collect::<Result<Vec<Vec<u8>>>>()?;
    let status = doc.import_batch(&blobs).map_err(to_r_error)?;
    Ok(status_to_r(&status))
}

/// Whether the document lacks history before some version.
/// @noRd
#[extendr]
fn loro_doc_is_shallow_impl(doc: DocPtr) -> bool {
    doc.is_shallow()
}

/// Describe an exported blob without importing it.
/// @noRd
#[extendr]
fn loro_blob_metadata_impl(bytes: Raw) -> Result<Robj> {
    let meta = LoroDoc::decode_import_blob_meta(bytes.as_slice(), true).map_err(to_r_error)?;
    Ok(list!(
        mode = meta.mode.to_string(),
        changes = meta.change_num as i32,
        start_timestamp = meta.start_timestamp as f64,
        end_timestamp = meta.end_timestamp as f64,
        start_frontiers = Raw::from_bytes(&meta.start_frontiers.encode()),
        start_version = Raw::from_bytes(&meta.partial_start_vv.encode()),
        end_version = Raw::from_bytes(&meta.partial_end_vv.encode())
    )
    .into())
}

fn to_version(bytes: Nullable<Raw>, default: VersionVector) -> Result<VersionVector> {
    match bytes {
        Nullable::NotNull(bytes) => VersionVector::decode(bytes.as_slice()).map_err(to_r_error),
        Nullable::Null => Ok(default),
    }
}

/// Export the changes between two encoded version vectors as JSON text.
/// @noRd
#[extendr]
fn loro_doc_export_json_impl(
    doc: DocPtr,
    from: Nullable<Raw>,
    to: Nullable<Raw>,
) -> Result<String> {
    let from = to_version(from, VersionVector::default())?;
    let to = to_version(to, doc.oplog_vv())?;
    let json = doc.export_json_updates(&from, &to).map_err(to_r_error)?;
    serde_json::to_string(&json).map_err(to_r_error)
}

/// Import changes from JSON text produced by `loro_doc_export_json_impl`.
/// @noRd
#[extendr]
fn loro_doc_import_json_impl(doc: DocPtr, json: &str) -> Result<Robj> {
    // Loro reports unparseable JSON with an unrelated error message.
    let schema = JsonSchema::try_from(json).map_err(|_| {
        Error::Other(
            "json is not valid Loro JSON updates (values nested more than about 120 levels deep cannot be read from JSON)"
                .to_string(),
        )
    })?;
    let status = doc.import_json_updates(schema).map_err(to_r_error)?;
    Ok(status_to_r(&status))
}

/// Value or container at a slash-separated path; `NULL` when absent.
/// @noRd
#[extendr]
fn loro_doc_get_path_impl(doc: DocPtr, path: &str) -> Result<Robj> {
    match doc.get_by_str_path(path) {
        Some(item) => value_or_container_to_r(item),
        None => Ok(().into()),
    }
}

/// Values and containers matching a JSONPath expression.
/// @noRd
#[extendr]
fn loro_doc_jsonpath_impl(doc: DocPtr, path: &str) -> Result<List> {
    let matches = doc.jsonpath(path).map_err(to_r_error)?;
    let values = matches
        .into_iter()
        .map(value_or_container_to_r)
        .collect::<Result<Vec<Robj>>>()?;
    Ok(List::from_values(values))
}

/// Apply to `doc` the changes `source` made between two encoded frontiers.
/// @noRd
#[extendr]
fn loro_doc_apply_diff_impl(doc: DocPtr, source: DocPtr, from: Raw, to: Raw) -> Result<()> {
    let batch = source
        .diff(&to_frontiers(&from)?, &to_frontiers(&to)?)
        .map_err(to_r_error)?;
    doc.apply_diff(batch).map_err(to_r_error)?;
    // Loro leaves the applied changes in the open transaction.
    doc.commit();
    Ok(())
}

/// Deep value of the whole document as nested R lists.
/// @noRd
#[extendr]
fn loro_doc_value_impl(doc: DocPtr) -> Result<Robj> {
    container_value::doc_to_r(&doc)
}

/// Root container of the given `kind`.
/// @noRd
#[extendr]
fn loro_doc_container_impl(doc: DocPtr, name: &str, kind: &str) -> Result<Robj> {
    let container = match kind {
        "text" => Container::Text(doc.get_text(name)),
        "map" => Container::Map(doc.get_map(name)),
        "list" => Container::List(doc.get_list(name)),
        "movable_list" => Container::MovableList(doc.get_movable_list(name)),
        "counter" => Container::Counter(doc.get_counter(name)),
        "tree" => Container::Tree(doc.get_tree(name)),
        _ => return Err(Error::Other(format!("unknown container type: {kind}"))),
    };
    container_ref(container)
}

/// A handle to a new container of `kind` that belongs to no document.
/// @noRd
#[extendr]
fn loro_container_new_impl(kind: &str) -> Result<Robj> {
    container_ref(detached_container(kind)?)
}

/// Whether the container belongs to a document. A detached container that
/// has since been stored in one is first swapped for the attached copy, so
/// every R handle to it follows the container into the document.
/// @noRd
#[extendr]
fn loro_container_resolve_impl(mut container: ContainerPtr) -> bool {
    if !container.is_attached() {
        if let Some(attached) = container.get_attached() {
            *container = attached;
        }
    }
    container.is_attached()
}

/// Container id as a string.
/// @noRd
#[extendr]
fn loro_container_id_impl(container: ContainerPtr) -> String {
    container.id().to_string()
}

/// Contents of a container; child containers are expanded when `deep`
/// and given by id otherwise.
/// @noRd
#[extendr]
fn loro_container_value_impl(container: ContainerPtr, deep: bool) -> Result<Robj> {
    if kind_of(&container).is_none() {
        return Err(Error::Other("unsupported container type".to_string()));
    }
    container_value::container_to_r(&container, deep)
}

/// Whether the container has been removed from its document.
/// @noRd
#[extendr]
fn loro_container_is_deleted_impl(container: ContainerPtr) -> bool {
    container.is_deleted()
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

/// Set `key` to a detached container, which Loro copies into the map.
/// @noRd
#[extendr]
fn loro_map_attach_impl(map: ContainerPtr, key: &str, child: ContainerPtr) -> Result<()> {
    let map = as_map(&map)?;
    map.insert_container(key, (*child).clone())
        .map_err(to_r_error)?;
    Ok(())
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
    with_list!(list, |l| l.insert(pos, value).map_err(to_r_error))
}

/// Insert a detached container at a 0-based position.
/// @noRd
#[extendr]
fn loro_list_attach_impl(list: ContainerPtr, pos: i32, child: ContainerPtr) -> Result<()> {
    let pos = to_index(pos, "pos")?;
    let child = (*child).clone();
    with_list!(list, |l| l.insert_container(pos, child).map_err(to_r_error))?;
    Ok(())
}

/// Value or child container at a 0-based position.
/// @noRd
#[extendr]
fn loro_list_get_impl(list: ContainerPtr, pos: i32) -> Result<Robj> {
    let pos = to_index(pos, "pos")?;
    match with_list!(list, |l| l.get(pos)) {
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
    with_list!(list, |l| l.delete(pos, len).map_err(to_r_error))
}

/// Number of elements in a list.
/// @noRd
#[extendr]
fn loro_list_length_impl(list: ContainerPtr) -> Result<i32> {
    Ok(with_list!(list, |l| l.len()) as i32)
}

/// Replace the element of a movable list at a 0-based position.
/// @noRd
#[extendr]
fn loro_list_set_impl(list: ContainerPtr, pos: i32, value: Robj) -> Result<()> {
    let pos = to_index(pos, "pos")?;
    let value = r_to_value(&value)?;
    as_movable_list(&list)?.set(pos, value).map_err(to_r_error)
}

/// Replace the element of a movable list with a detached container.
/// @noRd
#[extendr]
fn loro_list_set_attach_impl(list: ContainerPtr, pos: i32, child: ContainerPtr) -> Result<()> {
    let pos = to_index(pos, "pos")?;
    as_movable_list(&list)?
        .set_container(pos, (*child).clone())
        .map_err(to_r_error)?;
    Ok(())
}

/// Move an element of a movable list between 0-based positions.
/// @noRd
#[extendr]
fn loro_list_move_impl(list: ContainerPtr, from: i32, to: i32) -> Result<()> {
    let from = to_index(from, "from")?;
    let to = to_index(to, "to")?;
    as_movable_list(&list)?.mov(from, to).map_err(to_r_error)
}

/// Add `by` to a counter.
/// @noRd
#[extendr]
fn loro_counter_increment_impl(counter: ContainerPtr, by: f64) -> Result<()> {
    as_counter(&counter)?.increment(by).map_err(to_r_error)
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

/// Rich text contents as a list of insert ops, for the whole text or the
/// 0-based code point range `[start, end)`.
/// @noRd
#[extendr]
fn loro_text_delta_impl(
    text: ContainerPtr,
    start: Nullable<i32>,
    end: Nullable<i32>,
) -> Result<Robj> {
    let text = as_text(&text)?;
    let delta = match (start, end) {
        (Nullable::NotNull(start), Nullable::NotNull(end)) => text
            .slice_delta(
                to_index(start, "start")?,
                to_index(end, "end")?,
                PosType::Unicode,
            )
            .map_err(to_r_error)?,
        _ => text.to_delta(),
    };
    Ok(delta::delta_to_r(delta))
}

/// Text in the 0-based code point range `[start, end)`.
/// @noRd
#[extendr]
fn loro_text_slice_impl(text: ContainerPtr, start: i32, end: i32) -> Result<String> {
    as_text(&text)?
        .slice(to_index(start, "start")?, to_index(end, "end")?)
        .map_err(to_r_error)
}

/// Replace `len` code points at a 0-based position; returns what was removed.
/// @noRd
#[extendr]
fn loro_text_splice_impl(text: ContainerPtr, pos: i32, len: i32, value: &str) -> Result<String> {
    as_text(&text)?
        .splice(to_index(pos, "pos")?, to_index(len, "len")?, value)
        .map_err(to_r_error)
}

/// Apply a list of retain / insert / delete ops.
/// @noRd
#[extendr]
fn loro_text_apply_delta_impl(text: ContainerPtr, delta: Robj) -> Result<()> {
    let delta = delta::delta_from_r(&delta)?;
    let text = as_text(&text)?;
    // Loro applies ops one at a time, so a delta that runs past the end
    // would otherwise fail part way through with earlier ops applied.
    let span = delta::delta_span(&delta);
    let length = text.len_unicode();
    if span > length {
        return Err(Error::Other(format!(
            "delta retains and deletes {span} characters, but the text has only {length}"
        )));
    }
    text.apply_delta(&delta).map_err(to_r_error)
}

/// Change the text to `value` by applying a minimal diff, computed over
/// characters or over whole lines.
/// @noRd
#[extendr]
fn loro_text_update_impl(text: ContainerPtr, value: &str, by_line: bool) -> Result<()> {
    let text = as_text(&text)?;
    if by_line {
        text.update_by_line(value, UpdateOptions::default())
    } else {
        text.update(value, UpdateOptions::default())
    }
    .map_err(to_r_error)
}

type SubscriptionPtr = ExternalPtr<events::QueuedSubscription>;

/// Queue change events for the whole document.
/// @noRd
#[extendr]
fn loro_doc_subscribe_impl(doc: DocPtr) -> SubscriptionPtr {
    let queue = events::EventQueue::new();
    let sink = queue.clone();
    let subscription = doc.subscribe_root(Arc::new(move |event| {
        sink.push(events::event_to_r(&event));
    }));
    ExternalPtr::new(events::QueuedSubscription::new(subscription, queue))
}

/// Queue change events for one container and its descendants.
/// @noRd
#[extendr]
fn loro_doc_subscribe_container_impl(doc: DocPtr, container: ContainerPtr) -> SubscriptionPtr {
    let queue = events::EventQueue::new();
    let sink = queue.clone();
    let subscription = doc.subscribe(
        &container.id(),
        Arc::new(move |event| {
            sink.push(events::event_to_r(&event));
        }),
    );
    ExternalPtr::new(events::QueuedSubscription::new(subscription, queue))
}

/// Queue the encoded updates produced by each local commit.
/// @noRd
#[extendr]
fn loro_doc_subscribe_local_updates_impl(doc: DocPtr) -> SubscriptionPtr {
    let queue = events::EventQueue::new();
    let sink = queue.clone();
    let subscription = doc.subscribe_local_update(Box::new(move |bytes| {
        sink.push(Raw::from_bytes(bytes).into());
        true
    }));
    ExternalPtr::new(events::QueuedSubscription::new(subscription, queue))
}

/// Whether any subscription has events waiting.
/// @noRd
#[extendr]
fn loro_events_pending_impl() -> bool {
    events::pending() > 0
}

/// Remove and return the queued events of a subscription.
/// @noRd
#[extendr]
fn loro_subscription_take_impl(subscription: SubscriptionPtr) -> List {
    subscription.take()
}

/// Stop a subscription and discard its queued events.
/// @noRd
#[extendr]
fn loro_subscription_cancel_impl(subscription: SubscriptionPtr) {
    subscription.cancel();
}

type UndoPtr = ExternalPtr<UndoManager>;

/// Create an undo manager tracking local changes to `doc`.
/// @noRd
#[extendr]
fn loro_undo_new_impl(
    doc: DocPtr,
    merge_interval: f64,
    max_steps: i32,
    exclude_origins: Vec<String>,
) -> Result<UndoPtr> {
    let mut manager = UndoManager::new(&doc);
    manager.set_merge_interval(merge_interval as i64);
    manager.set_max_undo_steps(to_index(max_steps, "max_steps")?);
    for prefix in &exclude_origins {
        manager.add_exclude_origin_prefix(prefix);
    }
    Ok(ExternalPtr::new(manager))
}

/// Empty the undo and redo stacks.
/// @noRd
#[extendr]
fn loro_undo_clear_impl(manager: UndoPtr) {
    manager.clear();
}

/// Pause (`TRUE`) or resume (`FALSE`) recording of local edits.
/// @noRd
#[extendr]
fn loro_undo_pause_impl(manager: UndoPtr, pause: bool) {
    if pause {
        manager.pause();
    } else {
        manager.resume();
    }
}

/// Whether recording is paused.
/// @noRd
#[extendr]
fn loro_undo_is_paused_impl(manager: UndoPtr) -> bool {
    manager.is_paused()
}

/// Undo one step; returns whether anything changed.
/// @noRd
#[extendr]
fn loro_undo_undo_impl(mut manager: UndoPtr) -> Result<bool> {
    manager.undo().map_err(to_r_error)
}

/// Redo one step; returns whether anything changed.
/// @noRd
#[extendr]
fn loro_undo_redo_impl(mut manager: UndoPtr) -> Result<bool> {
    manager.redo().map_err(to_r_error)
}

/// Number of available undo and redo steps.
/// @noRd
#[extendr]
fn loro_undo_counts_impl(manager: UndoPtr) -> Vec<i32> {
    vec![manager.undo_count() as i32, manager.redo_count() as i32]
}

/// Start (`TRUE`) or end (`FALSE`) a group of changes undone as one step.
/// @noRd
#[extendr]
fn loro_undo_group_impl(mut manager: UndoPtr, start: bool) -> Result<()> {
    if start {
        manager.group_start().map_err(to_r_error)
    } else {
        manager.group_end();
        Ok(())
    }
}

type EphemeralPtr = ExternalPtr<EphemeralStore>;

/// Create an ephemeral store whose entries expire after `timeout` ms.
/// @noRd
#[extendr]
fn loro_ephemeral_new_impl(timeout: f64) -> EphemeralPtr {
    ExternalPtr::new(EphemeralStore::new(timeout as i64))
}

/// Set `key` to a plain value.
/// @noRd
#[extendr]
fn loro_ephemeral_set_impl(store: EphemeralPtr, key: &str, value: Robj) -> Result<()> {
    store.set(key, r_to_value(&value)?);
    Ok(())
}

/// Value at `key`; `NULL` when absent.
/// @noRd
#[extendr]
fn loro_ephemeral_get_impl(store: EphemeralPtr, key: &str) -> Robj {
    let store: &EphemeralStore = &store;
    match store.get(key) {
        Some(value) => value_to_r(&value),
        None => ().into(),
    }
}

/// Remove `key`.
/// @noRd
#[extendr]
fn loro_ephemeral_delete_impl(store: EphemeralPtr, key: &str) {
    store.delete(key);
}

/// Sorted keys of the store.
/// @noRd
#[extendr]
fn loro_ephemeral_keys_impl(store: EphemeralPtr) -> Vec<String> {
    let mut keys = store.keys();
    keys.sort();
    keys
}

/// All entries as a named list, sorted by key.
/// @noRd
#[extendr]
fn loro_ephemeral_values_impl(store: EphemeralPtr) -> Result<Robj> {
    let mut entries: Vec<(String, Robj)> = store
        .get_all_states()
        .iter()
        .map(|(key, value)| (key.clone(), value_to_r(value)))
        .collect();
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    let (names, values): (Vec<String>, Vec<Robj>) = entries.into_iter().unzip();
    Ok(List::from_names_and_values(names, values)?.into())
}

/// Encode one key, or every key when `key` is `NULL`.
/// @noRd
#[extendr]
fn loro_ephemeral_encode_impl(store: EphemeralPtr, key: Nullable<String>) -> Raw {
    match key {
        Nullable::NotNull(key) => Raw::from_bytes(&store.encode(&key)),
        Nullable::Null => Raw::from_bytes(&store.encode_all()),
    }
}

/// Apply entries encoded by another store.
/// @noRd
#[extendr]
fn loro_ephemeral_apply_impl(store: EphemeralPtr, bytes: Raw) -> Result<()> {
    store.apply(bytes.as_slice()).map_err(to_r_error)
}

/// Drop entries that have not been updated within the timeout.
/// @noRd
#[extendr]
fn loro_ephemeral_remove_outdated_impl(store: EphemeralPtr) {
    store.remove_outdated();
}

/// Queue the store's change events.
/// @noRd
#[extendr]
fn loro_ephemeral_subscribe_impl(store: EphemeralPtr) -> SubscriptionPtr {
    let queue = events::EventQueue::new();
    let sink = queue.clone();
    let subscription = store.subscribe(Box::new(move |event| {
        sink.push(events::ephemeral_event_to_r(event));
        true
    }));
    ExternalPtr::new(events::QueuedSubscription::new(subscription, queue))
}

/// Queue the encoded updates produced by each local change to the store.
/// @noRd
#[extendr]
fn loro_ephemeral_subscribe_local_updates_impl(store: EphemeralPtr) -> SubscriptionPtr {
    let queue = events::EventQueue::new();
    let sink = queue.clone();
    let subscription = store.subscribe_local_updates(Box::new(move |bytes| {
        sink.push(Raw::from_bytes(bytes).into());
        true
    }));
    ExternalPtr::new(events::QueuedSubscription::new(subscription, queue))
}

fn is_live_node(tree: &LoroTree, node: TreeID) -> bool {
    tree.contains(node) && !tree.is_node_deleted(&node).unwrap_or(true)
}

/// Loro treats a node inside a deleted subtree as still movable (moving it
/// out revives the subtree) and deletable. Both contradict what
/// `tree_contains()` reports, so only live nodes may be moved or deleted.
fn to_live_node(tree: &LoroTree, node: &str) -> Result<TreeID> {
    let id = to_node(node)?;
    if !is_live_node(tree, id) {
        return Err(Error::Other(format!(
            "node {node} does not exist or has been deleted"
        )));
    }
    Ok(id)
}

/// Check a 0-based sibling index, reporting it in R's 1-based terms.
fn check_tree_index(index: usize, max: usize) -> Result<usize> {
    if index > max {
        return Err(Error::Other(format!(
            "`index` must be at most {}, not {}",
            max + 1,
            index + 1
        )));
    }
    Ok(index)
}

/// Create a node under `parent` (`NULL` for a root node), at a 0-based
/// `index` among its siblings or last when `NULL`. Returns the node id.
/// @noRd
#[extendr]
fn loro_tree_create_impl(
    tree: ContainerPtr,
    parent: Nullable<String>,
    index: Nullable<i32>,
) -> Result<String> {
    let tree = as_tree(&tree)?;
    let parent = to_live_parent(tree, parent)?;
    let node = match index {
        Nullable::Null => tree.create(parent),
        Nullable::NotNull(index) => {
            let siblings = tree.children_num(parent).unwrap_or(0);
            let index = check_tree_index(to_index(index, "index")?, siblings)?;
            tree.create_at(parent, index)
        }
    };
    Ok(node.map_err(to_r_error)?.to_string())
}

/// Move a node under `parent`, at a 0-based `index` or last when `NULL`.
/// @noRd
#[extendr]
fn loro_tree_move_impl(
    tree: ContainerPtr,
    node: &str,
    parent: Nullable<String>,
    index: Nullable<i32>,
) -> Result<()> {
    let tree = as_tree(&tree)?;
    let node = to_live_node(tree, node)?;
    let parent = to_live_parent(tree, parent)?;
    match index {
        Nullable::Null => tree.mov(node, parent),
        Nullable::NotNull(index) => {
            let siblings = tree.children_num(parent).unwrap_or(0);
            // Within its own parent the node is taken out before it is put
            // back, so the last valid position is one lower.
            let max = if tree.parent(node) == Some(parent) {
                siblings.saturating_sub(1)
            } else {
                siblings
            };
            let index = check_tree_index(to_index(index, "index")?, max)?;
            tree.mov_to(node, parent, index)
        }
    }
    .map_err(to_r_error)
}

/// Delete a node and its descendants.
/// @noRd
#[extendr]
fn loro_tree_delete_impl(tree: ContainerPtr, node: &str) -> Result<()> {
    let tree = as_tree(&tree)?;
    let node = to_live_node(tree, node)?;
    tree.delete(node).map_err(to_r_error)
}

/// The metadata map of a node. A deleted node's metadata can still be read.
/// @noRd
#[extendr]
fn loro_tree_meta_impl(tree: ContainerPtr, node: &str) -> Result<Robj> {
    let tree = as_tree(&tree)?;
    let id = to_node(node)?;
    if !tree.contains(id) {
        return Err(Error::Other(format!("node {node} does not exist")));
    }
    let meta = tree.get_meta(id).map_err(to_r_error)?;
    container_ref(Container::Map(meta))
}

/// Whether a node exists and has not been deleted.
/// @noRd
#[extendr]
fn loro_tree_contains_impl(tree: ContainerPtr, node: &str) -> Result<bool> {
    let tree = as_tree(&tree)?;
    let node = to_node(node)?;
    Ok(is_live_node(tree, node))
}

/// Ordered child ids of `parent` (`NULL` for the root nodes).
/// @noRd
#[extendr]
fn loro_tree_children_impl(tree: ContainerPtr, parent: Nullable<String>) -> Result<Vec<String>> {
    let tree = as_tree(&tree)?;
    let parent = to_live_parent(tree, parent)?;
    // Loro returns `None` both for a missing parent and for one without children.
    let children = tree.children(parent).unwrap_or_default();
    Ok(children.iter().map(|id| id.to_string()).collect())
}

/// Column-wise table of live nodes: `id`, `parent` (`NA` for roots), and
/// 0-based `index` among siblings.
/// @noRd
#[extendr]
fn loro_tree_nodes_impl(tree: ContainerPtr) -> Result<Robj> {
    let nodes = as_tree(&tree)?.get_nodes(false);
    let id: Vec<String> = nodes.iter().map(|n| n.id.to_string()).collect();
    let parent: Vec<Rstr> = nodes
        .iter()
        .map(|n| history::parent_to_rstr(&n.parent))
        .collect();
    let index: Vec<i32> = nodes.iter().map(|n| n.index as i32).collect();
    Ok(list!(
        id = id,
        parent = Strings::from_values(parent),
        index = index
    )
    .into())
}

/// Remove every entry of a map.
/// @noRd
#[extendr]
fn loro_map_clear_impl(map: ContainerPtr) -> Result<()> {
    as_map(&map)?.clear().map_err(to_r_error)
}

/// The child container of `kind` at `key`, created if absent in a way
/// that merges with concurrent creation on other replicas.
/// @noRd
#[extendr]
fn loro_map_ensure_container_impl(map: ContainerPtr, key: &str, kind: &str) -> Result<Robj> {
    let map = as_map(&map)?;
    // Loro would otherwise create a second container of the new type
    // under the same key, hiding the existing one.
    if let Some(ValueOrContainer::Container(existing)) = map.get(key) {
        if kind_of(&existing) != Some(kind) {
            return Err(Error::Other(format!(
                "key already holds a {} container",
                kind_of(&existing).unwrap_or("different")
            )));
        }
    }
    let child = match kind {
        "text" => Container::Text(map.ensure_mergeable_text(key).map_err(to_r_error)?),
        "map" => Container::Map(map.ensure_mergeable_map(key).map_err(to_r_error)?),
        "list" => Container::List(map.ensure_mergeable_list(key).map_err(to_r_error)?),
        "movable_list" => {
            Container::MovableList(map.ensure_mergeable_movable_list(key).map_err(to_r_error)?)
        }
        "counter" => Container::Counter(map.ensure_mergeable_counter(key).map_err(to_r_error)?),
        "tree" => Container::Tree(map.ensure_mergeable_tree(key).map_err(to_r_error)?),
        _ => return Err(Error::Other(format!("unknown container type: {kind}"))),
    };
    container_ref(child)
}

/// Peer id that last wrote `key`, or `NA`.
/// @noRd
#[extendr]
fn loro_map_last_editor_impl(map: ContainerPtr, key: &str) -> Result<Rstr> {
    Ok(match as_map(&map)?.get_last_editor(key) {
        Some(peer) => Rstr::from(peer.to_string()),
        None => Rstr::na(),
    })
}

/// Remove and return the last element of a list; `NULL` when empty.
/// @noRd
#[extendr]
fn loro_list_pop_impl(list: ContainerPtr) -> Result<Robj> {
    let len = with_list!(list, |l| l.len());
    if len == 0 {
        return Ok(().into());
    }
    // Read before deleting: `LoroList::pop` returns a child container as
    // a bare id, after which its contents can no longer be read.
    let value = match with_list!(list, |l| l.get(len - 1)) {
        Some(item) => container_value::item_to_r(&item, true)?,
        None => ().into(),
    };
    with_list!(list, |l| l.delete(len - 1, 1).map_err(to_r_error))?;
    Ok(value)
}

/// Remove every element of a list.
/// @noRd
#[extendr]
fn loro_list_clear_impl(list: ContainerPtr) -> Result<()> {
    with_list!(list, |l| l.clear().map_err(to_r_error))
}

/// Version vector equivalent of encoded frontiers.
/// @noRd
#[extendr]
fn loro_doc_frontiers_to_version_impl(doc: DocPtr, frontiers: Raw) -> Result<Raw> {
    match doc.frontiers_to_vv(&to_frontiers(&frontiers)?) {
        Some(vv) => Ok(Raw::from_bytes(&vv.encode())),
        None => Err(Error::Other(
            "frontiers are not part of this document's history".to_string(),
        )),
    }
}

/// Frontiers equivalent of an encoded version vector.
/// @noRd
#[extendr]
fn loro_doc_version_to_frontiers_impl(doc: DocPtr, version: Raw) -> Result<Raw> {
    let vv = VersionVector::decode(version.as_slice()).map_err(to_r_error)?;
    Ok(Raw::from_bytes(&doc.vv_to_frontiers(&vv).encode()))
}

/// Order of two versions: -1, 0, or 1, or `NA` when they are concurrent.
/// @noRd
#[extendr]
fn loro_doc_compare_frontiers_impl(doc: DocPtr, a: Raw, b: Raw) -> Result<Rint> {
    let order = doc
        .cmp_frontiers(&to_frontiers(&a)?, &to_frontiers(&b)?)
        .map_err(to_r_error)?;
    Ok(match order {
        Some(std::cmp::Ordering::Less) => Rint::from(-1),
        Some(std::cmp::Ordering::Equal) => Rint::from(0),
        Some(std::cmp::Ordering::Greater) => Rint::from(1),
        None => Rint::na(),
    })
}

/// Number of operations and of changes in the document's history.
/// @noRd
#[extendr]
fn loro_doc_counts_impl(doc: DocPtr) -> Vec<i32> {
    vec![doc.len_ops() as i32, doc.len_changes() as i32]
}

fn to_id(peer: &str, counter: i32) -> Result<ID> {
    let peer: u64 = peer
        .parse()
        .map_err(|_| Error::Other(format!("not a valid peer id: {peer}")))?;
    Ok(ID::new(peer, counter))
}

/// Metadata of the change containing the operation `counter@peer`.
/// @noRd
#[extendr]
fn loro_doc_change_impl(doc: DocPtr, peer: &str, counter: i32) -> Result<Robj> {
    match doc.get_change(to_id(peer, counter)?) {
        Some(change) => Ok(history::change_metas_to_r(&[change])),
        None => Err(Error::Other(
            "no change contains that operation".to_string(),
        )),
    }
}

/// Ids of the containers changed by `length` operations from `counter@peer`.
/// @noRd
#[extendr]
fn loro_doc_changed_containers_impl(
    doc: DocPtr,
    peer: &str,
    counter: i32,
    length: i32,
) -> Result<Vec<String>> {
    let id = to_id(peer, counter)?;
    if doc.get_change(id).is_none() {
        return Err(Error::Other(
            "no change contains that operation".to_string(),
        ));
    }
    let mut ids: Vec<String> = doc
        .get_changed_containers_in(id, to_index(length, "length")?)
        .iter()
        .map(|id| id.to_string())
        .collect();
    ids.sort();
    Ok(ids)
}

/// Encoded cursor anchored at a 0-based list position.
/// @noRd
#[extendr]
fn loro_list_cursor_impl(list: ContainerPtr, pos: i32, side: i32) -> Result<Raw> {
    let pos = to_index(pos, "pos")?;
    let Some(side) = Side::from_i32(side) else {
        return Err(Error::Other("side must be -1, 0, or 1".to_string()));
    };
    match with_list!(list, |l| l.get_cursor(pos, side)) {
        Some(cursor) => Ok(Raw::from_bytes(&cursor.encode())),
        None => Err(Error::Other(
            "cannot create a cursor at this position".to_string(),
        )),
    }
}

/// Allow (`TRUE`) or forbid (`FALSE`) editing while detached.
/// @noRd
#[extendr]
fn loro_doc_set_detached_editing_impl(doc: DocPtr, enable: bool) {
    doc.set_detached_editing(enable);
}

/// Whether editing while detached is allowed.
/// @noRd
#[extendr]
fn loro_doc_is_detached_editing_impl(doc: DocPtr) -> bool {
    doc.is_detached_editing_enabled()
}

/// Stop the document state from following newly imported changes.
/// @noRd
#[extendr]
fn loro_doc_detach_impl(doc: DocPtr) {
    doc.detach();
}

fn to_pos_type(unit: &str) -> Result<PosType> {
    match unit {
        "unicode" => Ok(PosType::Unicode),
        "utf16" => Ok(PosType::Utf16),
        "utf8" => Ok(PosType::Bytes),
        _ => Err(Error::Other(format!("unknown unit: {unit}"))),
    }
}

/// Length of a text container in the given unit.
/// @noRd
#[extendr]
fn loro_text_length_unit_impl(text: ContainerPtr, unit: &str) -> Result<i32> {
    let text = as_text(&text)?;
    Ok(match to_pos_type(unit)? {
        PosType::Utf16 => text.len_utf16(),
        PosType::Bytes => text.len_utf8(),
        _ => text.len_unicode(),
    } as i32)
}

/// Convert a 0-based offset between units; `NA` when it is out of bounds
/// or falls inside a character.
/// @noRd
#[extendr]
fn loro_text_convert_pos_impl(text: ContainerPtr, pos: i32, from: &str, to: &str) -> Result<Rint> {
    let converted =
        as_text(&text)?.convert_pos(to_index(pos, "pos")?, to_pos_type(from)?, to_pos_type(to)?);
    Ok(match converted {
        Some(pos) => Rint::from(pos as i32),
        None => Rint::na(),
    })
}

/// Queue the new peer id each time the document's peer id changes.
/// @noRd
#[extendr]
fn loro_doc_subscribe_peer_id_impl(doc: DocPtr) -> SubscriptionPtr {
    let queue = events::EventQueue::new();
    let sink = queue.clone();
    let subscription = doc.subscribe_peer_id_change(Box::new(move |id| {
        sink.push(id.peer.to_string().into());
        true
    }));
    ExternalPtr::new(events::QueuedSubscription::new(subscription, queue))
}

/// Queue the peer id the first time each peer commits to this document.
/// @noRd
#[extendr]
fn loro_doc_subscribe_first_commit_impl(doc: DocPtr) -> SubscriptionPtr {
    let queue = events::EventQueue::new();
    let sink = queue.clone();
    let subscription = doc.subscribe_first_commit_from_peer(Box::new(move |payload| {
        sink.push(payload.peer.to_string().into());
        true
    }));
    ExternalPtr::new(events::QueuedSubscription::new(subscription, queue))
}

extendr_module! {
    mod creditor;
    fn loro_doc_new_impl;
    fn loro_doc_peer_id_impl;
    fn loro_doc_set_peer_id_impl;
    fn loro_doc_commit_impl;
    fn loro_doc_fork_impl;
    fn loro_doc_record_timestamps_impl;
    fn loro_frontiers_ids_impl;
    fn loro_doc_frontiers_impl;
    fn loro_doc_checkout_impl;
    fn loro_doc_is_detached_impl;
    fn loro_doc_revert_to_impl;
    fn loro_doc_diff_impl;
    fn loro_doc_changes_impl;
    fn loro_doc_version_impl;
    fn loro_doc_export_impl;
    fn loro_doc_import_impl;
    fn loro_doc_import_batch_impl;
    fn loro_doc_is_shallow_impl;
    fn loro_blob_metadata_impl;
    fn loro_doc_export_json_impl;
    fn loro_doc_import_json_impl;
    fn loro_doc_get_path_impl;
    fn loro_doc_jsonpath_impl;
    fn loro_doc_apply_diff_impl;
    fn loro_text_slice_impl;
    fn loro_text_splice_impl;
    fn loro_map_clear_impl;
    fn loro_map_ensure_container_impl;
    fn loro_map_last_editor_impl;
    fn loro_list_pop_impl;
    fn loro_list_clear_impl;
    fn loro_doc_value_impl;
    fn loro_doc_container_impl;
    fn loro_container_new_impl;
    fn loro_container_resolve_impl;
    fn loro_container_id_impl;
    fn loro_container_value_impl;
    fn loro_container_is_deleted_impl;
    fn loro_doc_frontiers_to_version_impl;
    fn loro_doc_version_to_frontiers_impl;
    fn loro_doc_compare_frontiers_impl;
    fn loro_doc_counts_impl;
    fn loro_doc_change_impl;
    fn loro_doc_changed_containers_impl;
    fn loro_list_cursor_impl;
    fn loro_undo_clear_impl;
    fn loro_undo_pause_impl;
    fn loro_undo_is_paused_impl;
    fn loro_text_insert_impl;
    fn loro_text_delete_impl;
    fn loro_text_length_impl;
    fn loro_text_length_unit_impl;
    fn loro_text_convert_pos_impl;
    fn loro_doc_set_detached_editing_impl;
    fn loro_doc_is_detached_editing_impl;
    fn loro_doc_detach_impl;
    fn loro_doc_subscribe_peer_id_impl;
    fn loro_doc_subscribe_first_commit_impl;
    fn loro_doc_config_text_style_impl;
    fn loro_doc_cursor_pos_impl;
    fn loro_text_cursor_impl;
    fn loro_text_mark_impl;
    fn loro_text_unmark_impl;
    fn loro_text_delta_impl;
    fn loro_text_apply_delta_impl;
    fn loro_text_update_impl;
    fn loro_doc_subscribe_impl;
    fn loro_doc_subscribe_container_impl;
    fn loro_doc_subscribe_local_updates_impl;
    fn loro_events_pending_impl;
    fn loro_subscription_take_impl;
    fn loro_subscription_cancel_impl;
    fn loro_undo_new_impl;
    fn loro_undo_undo_impl;
    fn loro_undo_redo_impl;
    fn loro_undo_counts_impl;
    fn loro_undo_group_impl;
    fn loro_ephemeral_new_impl;
    fn loro_ephemeral_set_impl;
    fn loro_ephemeral_get_impl;
    fn loro_ephemeral_delete_impl;
    fn loro_ephemeral_keys_impl;
    fn loro_ephemeral_values_impl;
    fn loro_ephemeral_encode_impl;
    fn loro_ephemeral_apply_impl;
    fn loro_ephemeral_remove_outdated_impl;
    fn loro_ephemeral_subscribe_impl;
    fn loro_ephemeral_subscribe_local_updates_impl;
    fn loro_map_set_impl;
    fn loro_map_attach_impl;
    fn loro_map_get_impl;
    fn loro_map_delete_impl;
    fn loro_map_keys_impl;
    fn loro_map_length_impl;
    fn loro_list_insert_impl;
    fn loro_list_attach_impl;
    fn loro_list_get_impl;
    fn loro_list_delete_impl;
    fn loro_list_length_impl;
    fn loro_list_set_impl;
    fn loro_list_set_attach_impl;
    fn loro_list_move_impl;
    fn loro_counter_increment_impl;
    fn loro_tree_create_impl;
    fn loro_tree_move_impl;
    fn loro_tree_delete_impl;
    fn loro_tree_meta_impl;
    fn loro_tree_contains_impl;
    fn loro_tree_children_impl;
    fn loro_tree_nodes_impl;
}
