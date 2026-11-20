use extendr_api::prelude::*;
use loro::{
    Container, ContainerTrait, LoroDoc, LoroTree, LoroValue, TreeParentId, ValueOrContainer,
};

use crate::history::parent_to_rstr;
use crate::value_to_r::value_to_r;

fn named_list(mut entries: Vec<(String, Robj)>) -> Robj {
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    let (names, values): (Vec<String>, Vec<Robj>) = entries.into_iter().unzip();
    match List::from_names_and_values(names, values) {
        Ok(list) => list.into(),
        Err(_) => ().into(),
    }
}

/// A plain value as is; a child container expanded when `deep`, or given
/// by its container id otherwise.
pub fn item_to_r(item: &ValueOrContainer, deep: bool) -> Robj {
    match item {
        ValueOrContainer::Value(value) => value_to_r(value),
        ValueOrContainer::Container(container) if deep => container_to_r(container, true),
        ValueOrContainer::Container(container) => container.id().to_string().into(),
    }
}

fn tree_level(tree: &LoroTree, parent: TreeParentId, deep: bool) -> Robj {
    let nodes: Vec<Robj> = tree
        .children(parent)
        .unwrap_or_default()
        .into_iter()
        .enumerate()
        .map(|(index, id)| {
            let position = match tree.fractional_index(id) {
                Some(position) => Rstr::from(position),
                None => Rstr::na(),
            };
            let meta = match tree.get_meta(id) {
                Ok(meta) => item_to_r(&ValueOrContainer::Container(Container::Map(meta)), deep),
                Err(_) => ().into(),
            };
            list!(
                id = id.to_string(),
                parent = parent_to_rstr(&parent),
                index = index as i32 + 1,
                fractional_index = position,
                meta = meta,
                children = tree_level(tree, TreeParentId::Node(id), deep)
            )
            .into()
        })
        .collect();
    List::from_values(nodes).into()
}

/// Contents of a container as R values.
///
/// This walks the handles rather than converting `get_deep_value()`,
/// because a `LoroValue` no longer says which container each part came
/// from: a tree's 0-based `index` could not be told apart from a map
/// entry that happens to be called `index`.
///
/// Items are collected before any child is visited so that no Loro
/// iteration is in progress while another container is read.
pub fn container_to_r(container: &Container, deep: bool) -> Robj {
    match container {
        Container::Text(text) => text.to_string().into(),
        Container::Counter(counter) => counter.get_value().into(),
        Container::Map(map) => {
            let mut items: Vec<(String, ValueOrContainer)> = Vec::new();
            map.for_each(|key, item| items.push((key.to_string(), item)));
            named_list(
                items
                    .iter()
                    .map(|(key, item)| (key.clone(), item_to_r(item, deep)))
                    .collect(),
            )
        }
        Container::List(list) => {
            let mut items: Vec<ValueOrContainer> = Vec::new();
            list.for_each(|item| items.push(item));
            let values: Vec<Robj> = items.iter().map(|item| item_to_r(item, deep)).collect();
            List::from_values(values).into()
        }
        Container::MovableList(list) => {
            let mut items: Vec<ValueOrContainer> = Vec::new();
            list.for_each(|item| items.push(item));
            let values: Vec<Robj> = items.iter().map(|item| item_to_r(item, deep)).collect();
            List::from_values(values).into()
        }
        Container::Tree(tree) => tree_level(tree, TreeParentId::Root, deep),
        _ => ().into(),
    }
}

/// Deep value of a whole document: one entry per root container.
pub fn doc_to_r(doc: &LoroDoc) -> Robj {
    let LoroValue::Map(roots) = doc.get_value() else {
        return named_list(Vec::new());
    };
    named_list(
        roots
            .iter()
            .map(|(name, value)| {
                let value = match value {
                    LoroValue::Container(id) => match doc.get_container(id.clone()) {
                        Some(container) => container_to_r(&container, true),
                        None => ().into(),
                    },
                    other => value_to_r(other),
                };
                (name.clone(), value)
            })
            .collect(),
    )
}
