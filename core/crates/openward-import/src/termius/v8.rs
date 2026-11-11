//! V8's value serialization, as Chromium's IndexedDB stores JavaScript
//! values: plain data only (objects, arrays, strings, numbers, booleans,
//! dates, null). Anything else, such as a Map, a typed array or a host
//! object, is an error: an app's settings never hold one.

use std::collections::BTreeMap;

use super::budget::{Budget, MAX_ARRAY, MAX_DEPTH};
use super::leveldb::Reader;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Undefined,
    Null,
    Bool(bool),
    Int(i64),
    Double(f64),
    String(String),
    Date(f64),
    Array(Vec<Value>),
    Object(BTreeMap<String, Value>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(map) => map.get(key),
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::String(s) => Some(s),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        match self {
            Value::Int(n) => Some(*n),
            Value::Double(d) if d.fract() == 0.0 && d.abs() < 9.0e15 => Some(*d as i64),
            Value::String(s) => s.trim().parse().ok(),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            Value::Int(n) => Some(*n != 0),
            _ => None,
        }
    }

    /// `null` and `undefined` both mean "not set".
    pub fn is_unset(&self) -> bool {
        matches!(self, Value::Null | Value::Undefined)
    }
}

/// A V8-serialized value, starting at its `0xFF` version header.
pub fn deserialize(data: &[u8]) -> Result<Value, String> {
    deserialize_with_budget(data, &mut Budget::default())
}

pub(super) fn deserialize_with_budget(data: &[u8], budget: &mut Budget) -> Result<Value, String> {
    let mut d = Deserializer {
        r: Reader::new(data),
        objects: Vec::new(),
        budget,
    };
    d.header()?;
    d.value(0)
}

struct Deserializer<'a, 'b> {
    r: Reader<'a>,
    /// Values that later `^` references point at, by id.
    objects: Vec<Value>,
    budget: &'b mut Budget,
}

impl Deserializer<'_, '_> {
    fn header(&mut self) -> Result<(), String> {
        if self.r.byte()? != 0xff {
            return Err("no V8 version header".into());
        }
        let version = self.r.varint()?;
        if !(13..=16).contains(&version) {
            return Err(format!(
                "V8 serialization version {version} is not supported"
            ));
        }
        Ok(())
    }

    /// The next tag, past any padding.
    fn tag(&mut self) -> Result<u8, String> {
        loop {
            self.budget.work(1)?;
            match self.r.byte()? {
                0 => continue,
                t => return Ok(t),
            }
        }
    }

    fn peek_tag(&mut self) -> Result<u8, String> {
        let at = self.r.pos;
        let t = self.tag()?;
        self.r.pos = at;
        Ok(t)
    }

    fn value(&mut self, depth: usize) -> Result<Value, String> {
        if depth > MAX_DEPTH {
            return self.budget.refuse();
        }
        self.budget.allocation(1, size_of::<Value>())?;
        let tag = self.tag()?;
        Ok(match tag {
            b'_' => Value::Undefined,
            b'0' => Value::Null,
            b'T' => Value::Bool(true),
            b'F' => Value::Bool(false),
            b'I' => {
                let u = self.r.varint()?;
                Value::Int(((u >> 1) as i64) ^ -((u & 1) as i64))
            }
            b'U' => Value::Int(self.r.varint()? as i64),
            b'N' => Value::Double(self.double()?),
            b'"' => {
                let n = self.r.len()?;
                // Latin-1: each byte is the code point.
                self.budget.buffer(n, 2)?;
                Value::String(self.r.bytes(n)?.iter().map(|&b| b as char).collect())
            }
            b'c' => Value::String(self.two_byte()?),
            b'S' => {
                let n = self.r.len()?;
                self.budget.bytes(n)?;
                Value::String(
                    String::from_utf8(self.r.bytes(n)?.to_vec()).map_err(|_| "bad UTF-8 string")?,
                )
            }
            b'D' => {
                let v = Value::Date(self.double()?);
                let id = self.reserve()?;
                self.fill(id, v, depth)?
            }
            b'^' => {
                let id = self.r.len()?;
                let value = self
                    .objects
                    .get(id)
                    .ok_or("reference to an unknown object")?;
                copy_value(value, depth, self.budget)?
            }
            b'o' => {
                let id = self.reserve()?;
                let map = self.properties(b'{', depth)?;
                self.r.varint()?; // property count
                self.fill(id, Value::Object(map), depth)?
            }
            b'A' => {
                let id = self.reserve()?;
                let len = self.r.len()?;
                self.array_slots(len)?;
                if len > self.r.rest().len() {
                    return Err("array longer than the data".into());
                }
                let mut items = Vec::with_capacity(len);
                for _ in 0..len {
                    if self.peek_tag()? == b'-' {
                        self.tag()?;
                        items.push(Value::Undefined);
                    } else {
                        items.push(self.value(depth + 1)?);
                    }
                }
                // Extra properties of the array, if any, are dropped.
                self.properties(b'$', depth)?;
                self.r.varint()?;
                self.r.varint()?;
                self.fill(id, Value::Array(items), depth)?
            }
            b'a' => {
                let id = self.reserve()?;
                let len = self.r.len()?;
                self.array_slots(len)?;
                let props = self.properties(b'@', depth)?;
                self.r.varint()?;
                self.r.varint()?;
                let mut items = vec![Value::Undefined; len];
                for (k, v) in props {
                    if let Ok(i) = k.parse::<usize>()
                        && i < items.len()
                    {
                        items[i] = v;
                    }
                }
                self.fill(id, Value::Array(items), depth)?
            }
            b'y' | b'x' => {
                let v = Value::Bool(tag == b'y');
                let id = self.reserve()?;
                self.fill(id, v, depth)?
            }
            b'n' => {
                let v = Value::Double(self.double()?);
                let id = self.reserve()?;
                self.fill(id, v, depth)?
            }
            b's' => {
                let id = self.reserve()?;
                let v = self.value(depth + 1)?;
                self.fill(id, v, depth)?
            }
            other => {
                return Err(format!(
                    "V8 value of kind {:?} is not supported",
                    other as char
                ));
            }
        })
    }

    /// Key and value pairs up to `end`. Keys are strings or numbers.
    fn properties(&mut self, end: u8, depth: usize) -> Result<BTreeMap<String, Value>, String> {
        let mut map = BTreeMap::new();
        loop {
            if self.peek_tag()? == end {
                self.tag()?;
                return Ok(map);
            }
            let key = match self.value(depth + 1)? {
                Value::String(s) => s,
                Value::Int(n) => n.to_string(),
                Value::Double(d) => d.to_string(),
                _ => return Err("object key that is not a string or a number".into()),
            };
            let value = self.value(depth + 1)?;
            self.budget.allocation(1, 128)?;
            map.insert(key, value);
        }
    }

    /// Objects get their id before their contents, as V8 numbers them.
    fn reserve(&mut self) -> Result<usize, String> {
        self.budget.allocation(1, size_of::<Value>())?;
        self.objects.push(Value::Undefined);
        Ok(self.objects.len() - 1)
    }

    fn fill(&mut self, id: usize, v: Value, depth: usize) -> Result<Value, String> {
        self.objects[id] = copy_value(&v, depth, self.budget)?;
        Ok(v)
    }

    fn array_slots(&mut self, len: usize) -> Result<(), String> {
        if len > MAX_ARRAY {
            return self.budget.refuse();
        }
        self.budget.allocation(len, size_of::<Value>())
    }

    fn double(&mut self) -> Result<f64, String> {
        Ok(f64::from_le_bytes(self.r.bytes(8)?.try_into().unwrap()))
    }

    fn two_byte(&mut self) -> Result<String, String> {
        let n = self.r.len()?;
        if n % 2 != 0 {
            return Err("odd two-byte string length".into());
        }
        self.budget.buffer(n, 3)?;
        let units: Vec<u16> = self
            .r
            .bytes(n)?
            .chunks(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        String::from_utf16(&units).map_err(|_| "bad UTF-16 string".into())
    }
}

/// Charge the entire expanded tree, including map keys, before Clone allocates.
/// The depth check also covers shallow wire references to earlier deep values.
fn copy_value(value: &Value, depth: usize, budget: &mut Budget) -> Result<Value, String> {
    fn charge(value: &Value, depth: usize, budget: &mut Budget) -> Result<(), String> {
        if depth > MAX_DEPTH {
            return budget.refuse();
        }
        budget.allocation(1, size_of::<Value>())?;
        match value {
            Value::String(s) => budget.bytes(s.len())?,
            Value::Array(items) => {
                for item in items {
                    charge(item, depth + 1, budget)?;
                }
            }
            Value::Object(map) => {
                for (key, item) in map {
                    budget.bytes(key.len())?;
                    budget.allocation(1, 128)?;
                    charge(item, depth + 1, budget)?;
                }
            }
            _ => {}
        }
        Ok(())
    }
    charge(value, depth, budget)?;
    Ok(value.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    proptest::proptest! {
        /// What V8 would never write is an error, never a panic, a loop or
        /// a reservation the size of a number in the data.
        #[test]
        fn any_bytes_are_read_or_refused(bytes in proptest::collection::vec(proptest::prelude::any::<u8>(), 0..2048)) {
            let _ = deserialize(&bytes);
            let mut versioned = vec![0xFF, 0x0F];
            versioned.extend_from_slice(&bytes);
            let _ = deserialize(&versioned);
        }
    }

    fn obj(pairs: &[(&str, Value)]) -> Value {
        Value::Object(
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.clone()))
                .collect(),
        )
    }

    #[test]
    fn an_object_with_strings_numbers_and_an_array() {
        // {label: "web", port: 22, ok: true, tags: ["a"], when: null, n: -3}
        let mut data = vec![0xff, 15, b'o'];
        let s = |d: &mut Vec<u8>, t: &str| {
            d.push(b'"');
            d.push(t.len() as u8);
            d.extend_from_slice(t.as_bytes());
        };
        s(&mut data, "label");
        s(&mut data, "web");
        s(&mut data, "port");
        data.extend([b'I', 44]);
        s(&mut data, "ok");
        data.push(b'T');
        s(&mut data, "tags");
        data.extend([b'A', 1]);
        s(&mut data, "a");
        data.extend([b'$', 0, 1]);
        s(&mut data, "when");
        data.push(b'0');
        s(&mut data, "n");
        data.extend([b'I', 5]);
        data.extend([b'{', 6]);
        assert_eq!(
            deserialize(&data).unwrap(),
            obj(&[
                ("label", Value::String("web".into())),
                ("port", Value::Int(22)),
                ("ok", Value::Bool(true)),
                ("tags", Value::Array(vec![Value::String("a".into())])),
                ("when", Value::Null),
                ("n", Value::Int(-3)),
            ])
        );
    }

    #[test]
    fn a_two_byte_string_after_padding() {
        let mut data = vec![0xff, 15, 0, b'c', 4];
        data.extend("ñé".encode_utf16().flat_map(|u| u.to_le_bytes()));
        assert_eq!(deserialize(&data).unwrap(), Value::String("ñé".into()));
    }

    #[test]
    fn a_reference_to_an_earlier_object() {
        // [{}, <same object>]
        let data = [0xff, 15, b'A', 2, b'o', b'{', 0, b'^', 1, b'$', 0, 2];
        assert_eq!(
            deserialize(&data).unwrap(),
            Value::Array(vec![obj(&[]), obj(&[])])
        );
    }

    #[test]
    fn a_map_is_refused() {
        let err = deserialize(&[0xff, 15, b';', b':', 0]).unwrap_err();
        assert!(err.contains("';'"), "{err}");
    }

    fn varint(mut n: usize, out: &mut Vec<u8>) {
        while n >= 128 {
            out.push((n as u8 & 127) | 128);
            n >>= 7;
        }
        out.push(n as u8);
    }

    #[test]
    fn an_oversized_sparse_array_is_rejected_instead_of_truncated() {
        let mut data = vec![0xff, 15, b'a'];
        varint(65_537, &mut data);
        data.extend([b'@', 0]);
        varint(65_537, &mut data);
        assert!(deserialize(&data).is_err());
    }

    #[test]
    fn shallow_references_cannot_construct_an_unbounded_tree_height() {
        // Each child is shallow in the wire format, but points to its predecessor.
        let mut data = vec![0xff, 15, b'A', 70];
        data.extend([b'A', 0, b'$', 0, 0]);
        for previous in 1..70 {
            data.extend([b'A', 1, b'^', previous, b'$', 0, 1]);
        }
        data.extend([b'$', 0, 70]);
        assert!(deserialize(&data).is_err());
    }

    #[test]
    fn reference_expansion_is_charged_before_cloning() {
        let mut data = vec![0xff, 15, b'A', 18, b'A', 0, b'$', 0, 0];
        for previous in 1..18 {
            data.extend([b'A', 2, b'^', previous, b'^', previous, b'$', 0, 2]);
        }
        data.extend([b'$', 0, 18]);
        let mut budget = Budget::limited(128 << 10, 10_000, 10);
        assert!(deserialize_with_budget(&data, &mut budget).is_err());
        assert!(budget.exhausted);
    }
}
