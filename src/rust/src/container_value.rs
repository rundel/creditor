use extendr_api::Result;
use extendr_api::prelude::*;
use loro::{
    Container, ContainerTrait, LoroDoc, LoroTree, LoroValue, TreeParentId, ValueOrContainer,
};

use crate::history::parent_to_rstr;
use crate::value_to_r::value_to_r;

/// Nesting of containers (and of tree nodes) that will be expanded. The
/// walk recurses, and a document received from elsewhere can nest
/// containers deeply enough to overflow the C stack, which kills R.
const MAX_DEPTH: usize = 1000;

fn too_deep<T>() -> Result<T> {
    Err(Error::Other(format!(
        "containers are nested more than {MAX_DEPTH} levels deep; read them one level at a time (for a tree, with tree_nodes() or tree_children())"
    )))
}

fn named_list(mut entries: Vec<(String, Robj)>) -> Robj {
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    let (names, values): (Vec<String>, Vec<Robj>) = entries.into_iter().unzip();
    match List::from_names_and_values(names, values) {
        Ok(list) => list.into(),
        Err(_) => ().into(),
    }
}

fn item(item: &ValueOrContainer, deep: bool, depth: usize) -> Result<Robj> {
    match item {
        ValueOrContainer::Value(value) => Ok(value_to_r(value)),
        ValueOrContainer::Container(container) if deep => walk(container, true, depth + 1),
        ValueOrContainer::Container(container) => Ok(container.id().to_string().into()),
    }
}

/// A plain value as is; a child container expanded when `deep`, or given
/// by its container id otherwise.
pub fn item_to_r(value: &ValueOrContainer, deep: bool) -> Result<Robj> {
    item(value, deep, 0)
}

fn tree_level(tree: &LoroTree, parent: TreeParentId, deep: bool, depth: usize) -> Result<Robj> {
    if depth > MAX_DEPTH {
        return too_deep();
    }
    let nodes = tree
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
                Ok(meta) => item(
                    &ValueOrContainer::Container(Container::Map(meta)),
                    deep,
                    depth,
                )?,
                Err(_) => ().into(),
            };
            Ok(list!(
                id = id.to_string(),
                parent = parent_to_rstr(&parent),
                index = index as i32 + 1,
                fractional_index = position,
                meta = meta,
                children = tree_level(tree, TreeParentId::Node(id), deep, depth + 1)?
            )
            .into())
        })
        .collect::<Result<Vec<Robj>>>()?;
    Ok(List::from_values(nodes).into())
}

fn walk(container: &Container, deep: bool, depth: usize) -> Result<Robj> {
    if depth > MAX_DEPTH {
        return too_deep();
    }
    match container {
        Container::Text(text) => Ok(text.to_string().into()),
        Container::Counter(counter) => Ok(counter.get_value().into()),
        Container::Map(map) => {
            let mut items: Vec<(String, ValueOrContainer)> = Vec::new();
            map.for_each(|key, value| items.push((key.to_string(), value)));
            let entries = items
                .iter()
                .map(|(key, value)| Ok((key.clone(), item(value, deep, depth)?)))
                .collect::<Result<Vec<(String, Robj)>>>()?;
            Ok(named_list(entries))
        }
        Container::List(list) => {
            let mut items: Vec<ValueOrContainer> = Vec::new();
            list.for_each(|value| items.push(value));
            let values = items
                .iter()
                .map(|value| item(value, deep, depth))
                .collect::<Result<Vec<Robj>>>()?;
            Ok(List::from_values(values).into())
        }
        Container::MovableList(list) => {
            let mut items: Vec<ValueOrContainer> = Vec::new();
            list.for_each(|value| items.push(value));
            let values = items
                .iter()
                .map(|value| item(value, deep, depth))
                .collect::<Result<Vec<Robj>>>()?;
            Ok(List::from_values(values).into())
        }
        Container::Tree(tree) => tree_level(tree, TreeParentId::Root, deep, depth),
        _ => Ok(().into()),
    }
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
pub fn container_to_r(container: &Container, deep: bool) -> Result<Robj> {
    walk(container, deep, 0)
}

/// Deep value of a whole document: one entry per root container.
pub fn doc_to_r(doc: &LoroDoc) -> Result<Robj> {
    let LoroValue::Map(roots) = doc.get_value() else {
        return Ok(named_list(Vec::new()));
    };
    let entries = roots
        .iter()
        .map(|(name, value)| {
            let value = match value {
                LoroValue::Container(id) => match doc.get_container(id.clone()) {
                    Some(container) => walk(&container, true, 0)?,
                    None => ().into(),
                },
                other => value_to_r(other),
            };
            Ok((name.clone(), value))
        })
        .collect::<Result<Vec<(String, Robj)>>>()?;
    Ok(named_list(entries))
}
