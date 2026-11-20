use std::ops::ControlFlow;

use extendr_api::Result;
use extendr_api::prelude::*;
use loro::event::{Diff, DiffBatch, ListDiffItem};
use loro::{ChangeMeta, Frontiers, ID, LoroDoc, ValueOrContainer};

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

fn diff_to_r(diff: &Diff) -> Robj {
    match diff {
        Diff::Text(delta) => list!(type_ = "text", delta = delta_to_r(delta.clone())).into(),
        Diff::List(items) => list!(type_ = "list", delta = list_diff_to_r(items)).into(),
        Diff::Map(map) => {
            let mut entries: Vec<(&str, Robj)> = map
                .updated
                .iter()
                .map(|(key, value)| {
                    let value = match value {
                        Some(item) => item_to_r(item),
                        None => ().into(),
                    };
                    (key.as_ref(), value)
                })
                .collect();
            entries.sort_by(|a, b| a.0.cmp(b.0));
            let (names, values): (Vec<&str>, Vec<Robj>) = entries.into_iter().unzip();
            let updated: Robj = match List::from_names_and_values(names, values) {
                Ok(list) => list.into(),
                Err(_) => ().into(),
            };
            list!(type_ = "map", updated = updated).into()
        }
        _ => list!(type_ = "unsupported").into(),
    }
}

/// Named list with one entry per changed container, keyed by container id.
/// The `type_` field is renamed to `type` in R (`type` is a Rust keyword).
pub fn diff_batch_to_r(batch: &DiffBatch) -> Result<Robj> {
    let (names, values): (Vec<String>, Vec<Robj>) = batch
        .iter()
        .map(|(id, diff)| (id.to_string(), diff_to_r(diff)))
        .unzip();
    Ok(List::from_names_and_values(names, values)?.into())
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

    Ok(list!(
        peer = peer,
        counter = counter,
        lamport = lamport,
        length = length,
        timestamp = timestamp,
        message = Strings::from_values(message),
        frontiers = List::from_values(frontiers)
    )
    .into())
}
