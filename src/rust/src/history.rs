use std::ops::ControlFlow;

use extendr_api::Result;
use extendr_api::prelude::*;
use loro::event::{Diff, DiffBatch, ListDiffItem};
use loro::{
    ChangeMeta, ContainerID, Frontiers, ID, LoroDoc, TreeDiff, TreeExternalDiff, TreeParentId,
    ValueOrContainer,
};

use crate::delta::delta_to_r;
use crate::value_to_r::value_to_r;

fn item_to_r(item: &ValueOrContainer) -> Robj {
    value_to_r(&item.get_deep_value())
}

fn list_diff_to_r(items: &[ListDiffItem]) -> Robj {
    let ops: Vec<Robj> = items
        .iter()
        .map(|item| match item {
            ListDiffItem::Insert { insert, .. } => {
                let values: Vec<Robj> = insert.iter().map(item_to_r).collect();
                list!(insert = List::from_values(values)).into()
            }
            ListDiffItem::Delete { delete } => list!(delete = *delete as i32).into(),
            ListDiffItem::Retain { retain } => list!(retain = *retain as i32).into(),
        })
        .collect();
    List::from_values(ops).into()
}

/// Parent of a tree node as a string id, or `NA` when it is a root (or
/// has no live parent).
pub fn parent_to_rstr(parent: &TreeParentId) -> Rstr {
    match parent {
        TreeParentId::Node(id) => Rstr::from(id.to_string()),
        _ => Rstr::na(),
    }
}

fn tree_diff_to_r(diff: &TreeDiff) -> Robj {
    let items: Vec<Robj> = diff
        .diff
        .iter()
        .map(|item| {
            let node = item.target.to_string();
            match &item.action {
                TreeExternalDiff::Create { parent, index, .. } => list!(
                    node = node,
                    action = "create",
                    parent = parent_to_rstr(parent),
                    index = *index as i32 + 1
                )
                .into(),
                TreeExternalDiff::Move {
                    parent,
                    index,
                    old_parent,
                    old_index,
                    ..
                } => list!(
                    node = node,
                    action = "move",
                    parent = parent_to_rstr(parent),
                    index = *index as i32 + 1,
                    old_parent = parent_to_rstr(old_parent),
                    old_index = *old_index as i32 + 1
                )
                .into(),
                TreeExternalDiff::Delete {
                    old_parent,
                    old_index,
                } => list!(
                    node = node,
                    action = "delete",
                    old_parent = parent_to_rstr(old_parent),
                    old_index = *old_index as i32 + 1
                )
                .into(),
            }
        })
        .collect();
    List::from_values(items).into()
}

fn typed(kind: &str, field: &str, value: Robj) -> Robj {
    match List::from_names_and_values(["type", field], [Robj::from(kind), value]) {
        Ok(list) => list.into(),
        Err(_) => ().into(),
    }
}

fn diff_to_r(diff: &Diff) -> Robj {
    match diff {
        Diff::Text(delta) => typed("text", "delta", delta_to_r(delta.clone())),
        Diff::List(items) => typed("list", "delta", list_diff_to_r(items)),
        Diff::Map(map) => {
            let mut entries: Vec<(&str, Robj)> = Vec::new();
            let mut deleted: Vec<String> = Vec::new();
            for (key, value) in map.updated.iter() {
                match value {
                    Some(item) => entries.push((key.as_ref(), item_to_r(item))),
                    None => deleted.push(key.to_string()),
                }
            }
            entries.sort_by(|a, b| a.0.cmp(b.0));
            deleted.sort();
            let (names, values): (Vec<&str>, Vec<Robj>) = entries.into_iter().unzip();
            let updated: Robj = match List::from_names_and_values(names, values) {
                Ok(list) => list.into(),
                Err(_) => ().into(),
            };
            match List::from_names_and_values(
                ["type", "updated", "deleted"],
                [Robj::from("map"), updated, Robj::from(deleted)],
            ) {
                Ok(list) => list.into(),
                Err(_) => ().into(),
            }
        }
        Diff::Tree(tree) => typed("tree", "diff", tree_diff_to_r(tree)),
        Diff::Counter(increment) => typed("counter", "increment", (*increment).into()),
        _ => match List::from_names_and_values(["type"], [Robj::from("unsupported")]) {
            Ok(list) => list.into(),
            Err(_) => ().into(),
        },
    }
}

/// Named list with one entry per changed container, keyed by container id.
pub fn diffs_to_r<'a, 'b: 'a>(
    diffs: impl Iterator<Item = (&'a ContainerID, &'a Diff<'b>)>,
) -> Robj {
    let (names, values): (Vec<String>, Vec<Robj>) = diffs
        .map(|(id, diff)| (id.to_string(), diff_to_r(diff)))
        .unzip();
    match List::from_names_and_values(names, values) {
        Ok(list) => list.into(),
        Err(_) => ().into(),
    }
}

pub fn diff_batch_to_r(batch: &DiffBatch) -> Robj {
    diffs_to_r(batch.iter())
}

/// Column-wise metadata for every change in the oplog.
pub fn changes_to_r(doc: &LoroDoc) -> Result<Robj> {
    let heads: Vec<ID> = doc.oplog_frontiers().iter().collect();
    let mut changes: Vec<ChangeMeta> = Vec::new();
    doc.travel_change_ancestors(&heads, &mut |change| {
        changes.push(change);
        ControlFlow::Continue(())
    })
    .map_err(|e| Error::Other(e.to_string()))?;
    changes.sort_by(|a, b| (a.lamport, a.id.peer).cmp(&(b.lamport, b.id.peer)));

    Ok(change_metas_to_r(&changes))
}

/// Column-wise change metadata.
pub fn change_metas_to_r(changes: &[ChangeMeta]) -> Robj {
    let peer: Vec<String> = changes.iter().map(|c| c.id.peer.to_string()).collect();
    let counter: Vec<i32> = changes.iter().map(|c| c.id.counter).collect();
    let lamport: Vec<i32> = changes.iter().map(|c| c.lamport as i32).collect();
    let length: Vec<i32> = changes.iter().map(|c| c.len as i32).collect();
    let timestamp: Vec<f64> = changes.iter().map(|c| c.timestamp as f64).collect();
    let message: Vec<Rstr> = changes
        .iter()
        .map(|c| match &c.message {
            Some(message) => Rstr::from(message.as_ref()),
            None => Rstr::na(),
        })
        .collect();
    let frontiers: Vec<Robj> = changes
        .iter()
        .map(|c| {
            let last = ID::new(c.id.peer, c.id.counter + c.len as i32 - 1);
            Raw::from_bytes(&Frontiers::from_id(last).encode()).into()
        })
        .collect();

    list!(
        peer = peer,
        counter = counter,
        lamport = lamport,
        length = length,
        timestamp = timestamp,
        message = Strings::from_values(message),
        frontiers = List::from_values(frontiers)
    )
    .into()
}
