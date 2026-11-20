use extendr_api::Result;
use extendr_api::prelude::*;
use std::sync::Arc;

use loro::awareness::EphemeralStore;
use loro::cursor::{Cursor, Side};
use loro::{
    Container, ContainerTrait, ExpandType, ExportMode, Frontiers, LoroDoc, LoroList, LoroMap,
    LoroText, StyleConfig, StyleConfigMap, UndoManager, UpdateOptions, ValueOrContainer,
    VersionVector,
};

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

/// Commit the pending transaction, optionally with a message.
/// @noRd
#[extendr]
fn loro_doc_commit_impl(doc: DocPtr, message: Nullable<String>) {
    if let Nullable::NotNull(message) = message {
        doc.set_next_commit_message(&message);
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
        .map_err(to_r_error)
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
fn loro_undo_new_impl(doc: DocPtr, merge_interval: f64, max_steps: i32) -> Result<UndoPtr> {
    let mut manager = UndoManager::new(&doc);
    manager.set_merge_interval(merge_interval as i64);
    manager.set_max_undo_steps(to_index(max_steps, "max_steps")?);
    Ok(ExternalPtr::new(manager))
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

extendr_module! {
    mod creditor;
    fn loro_doc_new_impl;
    fn loro_doc_peer_id_impl;
    fn loro_doc_set_peer_id_impl;
    fn loro_doc_commit_impl;
    fn loro_doc_fork_impl;
    fn loro_doc_record_timestamps_impl;
    fn loro_doc_frontiers_impl;
    fn loro_doc_checkout_impl;
    fn loro_doc_is_detached_impl;
    fn loro_doc_revert_to_impl;
    fn loro_doc_diff_impl;
    fn loro_doc_changes_impl;
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
    fn loro_doc_subscribe_impl;
    fn loro_doc_subscribe_container_impl;
    fn loro_doc_subscribe_local_updates_impl;
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
