use extendr_api::prelude::*;
use loro::LoroValue;

pub fn value_to_r(value: &LoroValue) -> Robj {
    match value {
        LoroValue::Null => ().into(),
        LoroValue::Bool(b) => (*b).into(),
        LoroValue::Double(d) => (*d).into(),
        LoroValue::I64(i) => match i32::try_from(*i) {
            Ok(small) if small != i32::MIN => small.into(),
            _ => (*i as f64).into(),
        },
        LoroValue::Binary(b) => Raw::from_bytes(b.as_slice()).into(),
        LoroValue::String(s) => s.as_str().into(),
        LoroValue::List(items) => {
            let values: Vec<Robj> = items.iter().map(value_to_r).collect();
            List::from_values(values).into()
        }
        LoroValue::Map(map) => {
            let mut entries: Vec<(&String, &LoroValue)> = map.iter().collect();
            entries.sort_by(|a, b| a.0.cmp(b.0));
            let names: Vec<&str> = entries.iter().map(|(k, _)| k.as_str()).collect();
            let values: Vec<Robj> = entries.iter().map(|(_, v)| value_to_r(v)).collect();
            match List::from_names_and_values(names, values) {
                Ok(list) => list.into(),
                Err(_) => ().into(),
            }
        }
        LoroValue::Container(id) => id.to_string().into(),
    }
}
