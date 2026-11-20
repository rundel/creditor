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

fn names_of(robj: &Robj, len: usize) -> Result<Option<Vec<String>>> {
    let Some(names) = robj.names() else {
        return Ok(None);
    };
    let names: Vec<String> = names.map(|n| n.to_string()).collect();
    if names.iter().all(|n| n.is_empty()) {
        return Ok(None);
    }
    if names.len() != len || names.iter().any(|n| n.is_empty() || n == "NA") {
        return other("names must be either absent or all non-empty");
    }
    Ok(Some(names))
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
            let strings = Strings::try_from(robj.clone())?;
            let values = strings
                .iter()
                .map(|x| {
                    if x.is_na() {
                        LoroValue::Null
                    } else {
                        LoroValue::from(x.as_ref())
                    }
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
                .map(|v| r_to_value(&v))
                .collect::<Result<Vec<LoroValue>>>()?;
            collect(robj, values, false)
        }
        _ => unsupported(),
    }
}
