use std::collections::HashMap;

use extendr_api::Result;
use extendr_api::prelude::*;
use loro::LoroValue;

fn other<T>(msg: &str) -> Result<T> {
    Err(Error::Other(msg.to_string()))
}

fn unsupported<T>() -> Result<T> {
    other("only NULL, logical, numeric, character, raw, and list values can be stored")
}

/// Nesting allowed in a stored value. Conversion recurses, and an
/// unbounded depth overflows the C stack, which R cannot recover from.
const MAX_DEPTH: usize = 1000;

/// Elements of a character vector as owned UTF-8 strings, `None` for `NA`.
///
/// extendr hands out an R string's bytes as `&str` without checking them,
/// and Loro panics (poisoning the document) on text that is not valid
/// UTF-8. So strings are first translated by R, which handles latin1 and
/// native encodings, and then validated, which catches "bytes" strings
/// and malformed input that translation leaves alone.
pub fn utf8_strings(robj: &Robj) -> Result<Vec<Option<String>>> {
    let translated = call!("enc2utf8", robj.clone())?;
    let strings = Strings::try_from(translated)?;
    strings
        .iter()
        .map(|x| {
            if x.is_na() {
                return Ok(None);
            }
            let unchecked: &str = x.as_ref();
            match std::str::from_utf8(unchecked.as_bytes()) {
                Ok(valid) => Ok(Some(valid.to_string())),
                Err(_) => other("strings must be valid UTF-8"),
            }
        })
        .collect()
}

fn names_of(robj: &Robj, len: usize) -> Result<Option<Vec<String>>> {
    let Some(names) = robj.get_attrib("names") else {
        return Ok(None);
    };
    let names = utf8_strings(&names)?;
    if names.iter().all(|n| matches!(n.as_deref(), Some(""))) {
        return Ok(None);
    }
    if names.len() != len {
        return other("names must be either absent or all non-empty");
    }
    names
        .into_iter()
        .map(|name| match name {
            Some(name) if !name.is_empty() => Ok(name),
            _ => other("names must be either absent or all non-empty"),
        })
        .collect::<Result<Vec<String>>>()
        .map(Some)
}

fn collect(robj: &Robj, values: Vec<LoroValue>, scalar_ok: bool) -> Result<LoroValue> {
    match names_of(robj, values.len())? {
        Some(names) => {
            let map: HashMap<String, LoroValue> = names.into_iter().zip(values).collect();
            if map.len() != robj.len() {
                return other("names must be unique");
            }
            Ok(LoroValue::from(map))
        }
        None if scalar_ok && values.len() == 1 => Ok(values.into_iter().next().unwrap()),
        None => Ok(LoroValue::from(values)),
    }
}

pub fn r_to_value(robj: &Robj) -> Result<LoroValue> {
    convert(robj, 0)
}

fn convert(robj: &Robj, depth: usize) -> Result<LoroValue> {
    if depth > MAX_DEPTH {
        return Err(Error::Other(format!(
            "values nested more than {MAX_DEPTH} levels deep cannot be stored"
        )));
    }
    if robj.is_null() {
        return Ok(LoroValue::Null);
    }
    if robj.class().is_some() {
        return other("values with a class attribute cannot be stored");
    }
    // Zero-length R vectors have no valid data pointer to build a slice from.
    if robj.is_empty() {
        return match robj.rtype() {
            Rtype::Raw => Ok(LoroValue::from(Vec::<u8>::new())),
            Rtype::Logicals | Rtype::Integers | Rtype::Doubles | Rtype::Strings | Rtype::List => {
                Ok(LoroValue::from(Vec::<LoroValue>::new()))
            }
            _ => unsupported(),
        };
    }
    match robj.rtype() {
        Rtype::Logicals => {
            let values = robj
                .as_logical_slice()
                .unwrap_or_default()
                .iter()
                .map(|x| {
                    if x.is_na() {
                        LoroValue::Null
                    } else {
                        LoroValue::from(x.is_true())
                    }
                })
                .collect();
            collect(robj, values, true)
        }
        Rtype::Integers => {
            let values = robj
                .as_integer_slice()
                .unwrap_or_default()
                .iter()
                .map(|x| {
                    if x.is_na() {
                        LoroValue::Null
                    } else {
                        LoroValue::from(*x as i64)
                    }
                })
                .collect();
            collect(robj, values, true)
        }
        Rtype::Doubles => {
            let values = robj
                .as_real_slice()
                .unwrap_or_default()
                .iter()
                .map(|x| {
                    if x.is_na() {
                        LoroValue::Null
                    } else {
                        LoroValue::from(*x)
                    }
                })
                .collect();
            collect(robj, values, true)
        }
        Rtype::Strings => {
            let values = utf8_strings(robj)?
                .into_iter()
                .map(|x| match x {
                    Some(string) => LoroValue::from(string),
                    None => LoroValue::Null,
                })
                .collect();
            collect(robj, values, true)
        }
        Rtype::Raw => Ok(LoroValue::from(
            robj.as_raw_slice().unwrap_or_default().to_vec(),
        )),
        Rtype::List => {
            let list = List::try_from(robj.clone())?;
            let values = list
                .values()
                .map(|v| convert(&v, depth + 1))
                .collect::<Result<Vec<LoroValue>>>()?;
            collect(robj, values, false)
        }
        _ => unsupported(),
    }
}
