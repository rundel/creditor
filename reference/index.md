# Package index

## Documents

Create a document, identify its replica, and read its contents.

- [`loro_doc()`](https://rundel.github.io/creditor/reference/loro_doc.md)
  : Create a Loro document
- [`doc_peer_id()`](https://rundel.github.io/creditor/reference/doc.md)
  [`doc_set_peer_id()`](https://rundel.github.io/creditor/reference/doc.md)
  [`doc_fork()`](https://rundel.github.io/creditor/reference/doc.md)
  [`doc_commit()`](https://rundel.github.io/creditor/reference/doc.md)
  [`doc_value()`](https://rundel.github.io/creditor/reference/doc.md)
  [`doc_get()`](https://rundel.github.io/creditor/reference/doc.md)
  [`doc_jsonpath()`](https://rundel.github.io/creditor/reference/doc.md)
  : Document identity, replicas, and contents
- [`creditor`](https://rundel.github.io/creditor/reference/creditor-package.md)
  [`creditor-package`](https://rundel.github.io/creditor/reference/creditor-package.md)
  : creditor: R Interface to the Loro CRDT Library

## Containers

Documents hold containers. Get a handle to a root container or create a
new one to store inside a map or list.

- [`doc_text()`](https://rundel.github.io/creditor/reference/containers.md)
  [`doc_map()`](https://rundel.github.io/creditor/reference/containers.md)
  [`doc_list()`](https://rundel.github.io/creditor/reference/containers.md)
  [`doc_movable_list()`](https://rundel.github.io/creditor/reference/containers.md)
  [`doc_counter()`](https://rundel.github.io/creditor/reference/containers.md)
  [`doc_tree()`](https://rundel.github.io/creditor/reference/containers.md)
  [`container_value()`](https://rundel.github.io/creditor/reference/containers.md)
  [`container_is_deleted()`](https://rundel.github.io/creditor/reference/containers.md)
  [`container_id()`](https://rundel.github.io/creditor/reference/containers.md)
  : Container handles
- [`loro_text()`](https://rundel.github.io/creditor/reference/loro_text.md)
  [`loro_map()`](https://rundel.github.io/creditor/reference/loro_text.md)
  [`loro_list()`](https://rundel.github.io/creditor/reference/loro_text.md)
  [`loro_movable_list()`](https://rundel.github.io/creditor/reference/loro_text.md)
  [`loro_counter()`](https://rundel.github.io/creditor/reference/loro_text.md)
  [`loro_tree()`](https://rundel.github.io/creditor/reference/loro_text.md)
  : Create containers

## Editing containers

Each container type has its own functions, which take a handle (or a
document, standing for its default root container) as their first
argument.

- [`text_insert()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_push()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_delete()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_update()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_replace()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_sub()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_get()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_length()`](https://rundel.github.io/creditor/reference/text.md)
  [`text_convert_pos()`](https://rundel.github.io/creditor/reference/text.md)
  : Edit collaborative text
- [`text_mark()`](https://rundel.github.io/creditor/reference/richtext.md)
  [`text_unmark()`](https://rundel.github.io/creditor/reference/richtext.md)
  [`text_delta()`](https://rundel.github.io/creditor/reference/richtext.md)
  [`text_markdown()`](https://rundel.github.io/creditor/reference/richtext.md)
  [`text_ansi()`](https://rundel.github.io/creditor/reference/richtext.md)
  [`text_html()`](https://rundel.github.io/creditor/reference/richtext.md)
  [`text_apply_delta()`](https://rundel.github.io/creditor/reference/richtext.md)
  [`doc_config_text_style()`](https://rundel.github.io/creditor/reference/richtext.md)
  : Rich text
- [`text_cursor()`](https://rundel.github.io/creditor/reference/cursor.md)
  [`list_cursor()`](https://rundel.github.io/creditor/reference/cursor.md)
  [`cursor_pos()`](https://rundel.github.io/creditor/reference/cursor.md)
  : Cursors
- [`map_set()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_ensure_container()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_get()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_has()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_delete()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_clear()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_keys()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_length()`](https://rundel.github.io/creditor/reference/map.md)
  [`map_last_editor()`](https://rundel.github.io/creditor/reference/map.md)
  : Edit maps
- [`list_insert()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_push()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_get()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_delete()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_length()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_move()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_set()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_pop()`](https://rundel.github.io/creditor/reference/list.md)
  [`list_clear()`](https://rundel.github.io/creditor/reference/list.md)
  : Edit lists
- [`counter_increment()`](https://rundel.github.io/creditor/reference/counter.md)
  [`counter_get()`](https://rundel.github.io/creditor/reference/counter.md)
  : Counters
- [`tree_create()`](https://rundel.github.io/creditor/reference/tree.md)
  [`tree_move()`](https://rundel.github.io/creditor/reference/tree.md)
  [`tree_delete()`](https://rundel.github.io/creditor/reference/tree.md)
  [`tree_meta()`](https://rundel.github.io/creditor/reference/tree.md)
  [`tree_children()`](https://rundel.github.io/creditor/reference/tree.md)
  [`tree_nodes()`](https://rundel.github.io/creditor/reference/tree.md)
  [`tree_contains()`](https://rundel.github.io/creditor/reference/tree.md)
  : Trees

## Synchronization

Exchange snapshots and updates between replicas.

- [`doc_export()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_export_updates()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_export_shallow()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_import()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_merge()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_import_status()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_version()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_is_shallow()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`blob_metadata()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_export_json()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  [`doc_import_json()`](https://rundel.github.io/creditor/reference/doc_sync.md)
  : Synchronize documents
- [`as_version()`](https://rundel.github.io/creditor/reference/versions.md)
  [`as_frontiers()`](https://rundel.github.io/creditor/reference/versions.md)
  : Version objects

## History

List changes, compare versions, travel to earlier versions, and revert.

- [`doc_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_changes()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_change()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_change_count()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_op_count()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_changed_containers()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_frontiers_to_version()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_version_to_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_compare_frontiers()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_checkout()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_is_detached()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_detach()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_set_detached_editing()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_is_detached_editing()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_revert_to()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_diff()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_apply_diff()`](https://rundel.github.io/creditor/reference/history.md)
  [`doc_record_timestamps()`](https://rundel.github.io/creditor/reference/history.md)
  : Document history

## Events and undo

React to changes as they are committed and reverse local edits.

- [`doc_subscribe()`](https://rundel.github.io/creditor/reference/subscribe.md)
  [`doc_subscribe_local_updates()`](https://rundel.github.io/creditor/reference/subscribe.md)
  [`doc_subscribe_first_commit()`](https://rundel.github.io/creditor/reference/subscribe.md)
  [`doc_subscribe_peer_id()`](https://rundel.github.io/creditor/reference/subscribe.md)
  [`unsubscribe()`](https://rundel.github.io/creditor/reference/subscribe.md)
  : Subscribe to changes
- [`doc_undo_manager()`](https://rundel.github.io/creditor/reference/undo.md)
  [`undo_count()`](https://rundel.github.io/creditor/reference/undo.md)
  [`redo_count()`](https://rundel.github.io/creditor/reference/undo.md)
  [`undo_pause()`](https://rundel.github.io/creditor/reference/undo.md)
  [`undo_resume()`](https://rundel.github.io/creditor/reference/undo.md)
  [`undo_is_paused()`](https://rundel.github.io/creditor/reference/undo.md)
  [`undo_clear()`](https://rundel.github.io/creditor/reference/undo.md)
  [`undo()`](https://rundel.github.io/creditor/reference/undo.md)
  [`redo()`](https://rundel.github.io/creditor/reference/undo.md)
  [`can_undo()`](https://rundel.github.io/creditor/reference/undo.md)
  [`can_redo()`](https://rundel.github.io/creditor/reference/undo.md)
  [`undo_group()`](https://rundel.github.io/creditor/reference/undo.md)
  : Undo and redo

## Presence

Share short-lived state, such as cursors and user names, outside the
document.

- [`ephemeral_store()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_set()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_get()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_delete()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_keys()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_values()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_encode()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_apply()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_remove_outdated()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_subscribe()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  [`ephemeral_subscribe_local_updates()`](https://rundel.github.io/creditor/reference/ephemeral.md)
  : Ephemeral state
