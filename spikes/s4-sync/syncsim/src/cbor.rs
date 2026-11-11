//! Deterministic CBOR (RFC 8949 §4.2.1): definite lengths, the shortest
//! integers, and map keys sorted by their encoded bytes. `ciborium` already
//! writes the first two; the order of a map is ours to give.

use ciborium::Value;

pub fn encode(value: &Value) -> Vec<u8> {
    let mut out = Vec::new();
    ciborium::into_writer(value, &mut out).expect("writing to a Vec cannot fail");
    out
}

/// A map with its entries in deterministic order.
pub fn map(mut entries: Vec<(Value, Value)>) -> Value {
    entries.sort_by_cached_key(|(k, _)| encode(k));
    Value::Map(entries)
}

pub fn text_map<'a>(entries: impl IntoIterator<Item = (&'a str, Value)>) -> Value {
    map(entries
        .into_iter()
        .map(|(k, v)| (Value::Text(k.into()), v))
        .collect())
}

/// Decodes only what is written the one deterministic way: the same bytes
/// re-encode to themselves, and no map repeats or misorders a key. A
/// signature or a hash over the bytes then means one value.
pub fn decode_canonical(bytes: &[u8]) -> Option<Value> {
    let value: Value = ciborium::from_reader(bytes).ok()?;
    (sorted(&value) && encode(&value) == bytes).then_some(value)
}

fn sorted(value: &Value) -> bool {
    match value {
        Value::Map(entries) => {
            let keys: Vec<Vec<u8>> = entries.iter().map(|(k, _)| encode(k)).collect();
            keys.windows(2).all(|w| w[0] < w[1])
                && entries.iter().all(|(k, v)| sorted(k) && sorted(v))
        }
        Value::Array(items) => items.iter().all(sorted),
        Value::Tag(_, inner) => sorted(inner),
        _ => true,
    }
}

pub fn get<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a Value> {
    map.iter()
        .find(|(k, _)| k.as_text() == Some(key))
        .map(|(_, v)| v)
}

pub fn uint(value: &Value) -> Option<u64> {
    value.as_integer().and_then(|i| u64::try_from(i).ok())
}

pub fn bytes<const N: usize>(value: &Value) -> Option<[u8; N]> {
    value.as_bytes()?.as_slice().try_into().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_go_shortest_first_then_by_bytes() {
        let m = text_map([
            ("parents", Value::Null),
            ("v", Value::Null),
            ("ct", Value::Null),
            ("item", Value::Null),
        ]);
        let keys: Vec<_> = m
            .as_map()
            .unwrap()
            .iter()
            .map(|(k, _)| k.as_text().unwrap().to_string())
            .collect();
        assert_eq!(keys, ["v", "ct", "item", "parents"]);
    }

    #[test]
    fn only_the_deterministic_form_decodes() {
        let good = encode(&text_map([("a", Value::from(1)), ("bb", Value::from(2))]));
        assert!(decode_canonical(&good).is_some());
        // The same map with its keys swapped.
        let swapped = encode(&Value::Map(vec![
            (Value::Text("bb".into()), Value::from(2)),
            (Value::Text("a".into()), Value::from(1)),
        ]));
        assert!(decode_canonical(&swapped).is_none());
        // 1 written in two bytes instead of one.
        assert!(decode_canonical(&[0x18, 0x01]).is_none());
        // An indefinite-length array.
        assert!(decode_canonical(&[0x9f, 0x01, 0xff]).is_none());
    }
}
