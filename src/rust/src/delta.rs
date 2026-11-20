use extendr_api::Result;
use extendr_api::prelude::*;
use loro::{LoroValue, TextDelta};

use crate::r_to_value::{r_to_value, utf8_strings};
use crate::value_to_r::value_to_r;

fn other<T>(msg: &str) -> Result<T> {
    Err(Error::Other(msg.to_string()))
}

fn to_count(robj: &Robj, what: &str) -> Result<usize> {
    let value = robj
        .as_real()
        .or_else(|| robj.as_integer().map(|i| i as f64));
    match value {
        Some(x) if x >= 0.0 && x.fract() == 0.0 && x <= i32::MAX as f64 => Ok(x as usize),
        _ => Err(Error::Other(format!(
            "`{what}` must be a non-negative whole number"
        ))),
    }
}

fn attributes_to_r(
    attributes: Option<impl IntoIterator<Item = (String, LoroValue)>>,
) -> Option<Robj> {
    let mut entries: Vec<(String, LoroValue)> = attributes?.into_iter().collect();
    if entries.is_empty() {
        return None;
    }
    entries.sort_by(|a, b| a.0.cmp(&b.0));
    let names: Vec<&str> = entries.iter().map(|(k, _)| k.as_str()).collect();
    let values: Vec<Robj> = entries.iter().map(|(_, v)| value_to_r(v)).collect();
    List::from_names_and_values(names, values)
        .ok()
        .map(|l| l.into())
}

pub fn delta_to_r(delta: Vec<TextDelta>) -> Robj {
    let ops: Vec<Robj> = delta
        .into_iter()
        .map(|op| match op {
            TextDelta::Insert { insert, attributes } => match attributes_to_r(attributes) {
                Some(attributes) => list!(insert = insert, attributes = attributes).into(),
                None => list!(insert = insert).into(),
            },
            TextDelta::Retain { retain, attributes } => match attributes_to_r(attributes) {
                Some(attributes) => list!(retain = retain as i32, attributes = attributes).into(),
                None => list!(retain = retain as i32).into(),
            },
            TextDelta::Delete { delete } => list!(delete = delete as i32).into(),
        })
        .collect();
    List::from_values(ops).into()
}

fn op_from_r(op: &Robj) -> Result<TextDelta> {
    let Ok(fields) = List::try_from(op.clone()) else {
        return other("each delta op must be a named list");
    };
    let mut retain = None;
    let mut insert = None;
    let mut delete = None;
    let mut attributes = None;
    let mut seen: Vec<&str> = Vec::new();
    for (name, value) in fields.iter() {
        if seen.contains(&name) {
            return Err(Error::Other(format!(
                "delta op has more than one `{name}` field"
            )));
        }
        seen.push(name);
        match name {
            "retain" => retain = Some(to_count(&value, "retain")?),
            "delete" => delete = Some(to_count(&value, "delete")?),
            "insert" => {
                if value.rtype() != Rtype::Strings || value.len() != 1 {
                    return other("`insert` must be a single string");
                }
                match utf8_strings(&value)?.pop().flatten() {
                    Some(text) => insert = Some(text),
                    None => return other("`insert` must be a single string"),
                }
            }
            "attributes" => match r_to_value(&value)? {
                LoroValue::Map(map) => {
                    if map.keys().any(|key| key.contains(':')) {
                        return other("attribute names must not contain ':'");
                    }
                    attributes = Some(map.iter().map(|(k, v)| (k.clone(), v.clone())).collect());
                }
                LoroValue::List(list) if list.is_empty() => {}
                LoroValue::Null => {}
                _ => return other("`attributes` must be a named list"),
            },
            _ => {
                return other(
                    "delta op fields must be `retain`, `insert`, `delete`, or `attributes`",
                );
            }
        }
    }
    match (retain, insert, delete) {
        (Some(retain), None, None) => Ok(TextDelta::Retain { retain, attributes }),
        (None, Some(insert), None) => Ok(TextDelta::Insert { insert, attributes }),
        (None, None, Some(_)) if attributes.is_some() => {
            other("a `delete` op cannot have `attributes`")
        }
        (None, None, Some(delete)) => Ok(TextDelta::Delete { delete }),
        _ => other("each delta op must have exactly one of `retain`, `insert`, or `delete`"),
    }
}

pub fn delta_from_r(delta: &Robj) -> Result<Vec<TextDelta>> {
    let Ok(ops) = List::try_from(delta.clone()) else {
        return other("delta must be a list of ops");
    };
    ops.values().map(|op| op_from_r(&op)).collect()
}

/// Number of existing characters a delta walks over (its retains and
/// deletes), which must not exceed the length of the text it is applied to.
pub fn delta_span(delta: &[TextDelta]) -> usize {
    delta
        .iter()
        .map(|op| match op {
            TextDelta::Retain { retain, .. } => *retain,
            TextDelta::Delete { delete } => *delete,
            TextDelta::Insert { .. } => 0,
        })
        .sum()
}
