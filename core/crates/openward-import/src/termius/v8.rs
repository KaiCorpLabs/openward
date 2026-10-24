//! V8's value serialization, as Chromium's IndexedDB stores JavaScript
//! values: plain data only (objects, arrays, strings, numbers, booleans,
//! dates, null). Anything else, such as a Map, a typed array or a host
//! object, is an error: an app's settings never hold one.

use std::collections::BTreeMap;

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
    let mut d = Deserializer {
        r: Reader::new(data),
        objects: Vec::new(),
    };
    d.header()?;
    d.value(0)
}

const MAX_DEPTH: usize = 64;

struct Deserializer<'a> {
    r: Reader<'a>,
    /// Values that later `^` references point at, by id.
    objects: Vec<Value>,
}

impl Deserializer<'_> {
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
            return Err("value nested too deep".into());
        }
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
                Value::String(self.r.bytes(n)?.iter().map(|&b| b as char).collect())
            }
            b'c' => Value::String(self.two_byte()?),
            b'S' => {
                let n = self.r.len()?;
                Value::String(
                    String::from_utf8(self.r.bytes(n)?.to_vec()).map_err(|_| "bad UTF-8 string")?,
                )
            }
            b'D' => {
                let v = Value::Date(self.double()?);
                self.objects.push(v.clone());
                v
            }
            b'^' => {
                let id = self.r.len()?;
                self.objects
                    .get(id)
                    .cloned()
                    .ok_or("reference to an unknown object")?
            }
            b'o' => {
                let id = self.reserve();
                let map = self.properties(b'{', depth)?;
                self.r.varint()?; // property count
                self.fill(id, Value::Object(map))
            }
            b'A' => {
                let id = self.reserve();
                let len = self.r.len()?;
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
                self.fill(id, Value::Array(items))
            }
            b'a' => {
                let id = self.reserve();
                let len = self.r.len()?;
                let props = self.properties(b'@', depth)?;
                self.r.varint()?;
                self.r.varint()?;
                let mut items = vec![Value::Undefined; len.min(1 << 16)];
                for (k, v) in props {
                    if let Ok(i) = k.parse::<usize>()
                        && i < items.len()
                    {
                        items[i] = v;
                    }
                }
                self.fill(id, Value::Array(items))
            }
            b'y' | b'x' => {
                let v = Value::Bool(tag == b'y');
                self.objects.push(v.clone());
                v
            }
            b'n' => {
                let v = Value::Double(self.double()?);
                self.objects.push(v.clone());
                v
            }
            b's' => {
                let id = self.reserve();
                let v = self.value(depth + 1)?;
                self.fill(id, v)
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
            map.insert(key, value);
        }
    }

    /// Objects get their id before their contents, as V8 numbers them.
    fn reserve(&mut self) -> usize {
        self.objects.push(Value::Undefined);
        self.objects.len() - 1
    }

    fn fill(&mut self, id: usize, v: Value) -> Value {
        self.objects[id] = v.clone();
        v
    }

    fn double(&mut self) -> Result<f64, String> {
        Ok(f64::from_le_bytes(self.r.bytes(8)?.try_into().unwrap()))
    }

    fn two_byte(&mut self) -> Result<String, String> {
        let n = self.r.len()?;
        if n % 2 != 0 {
            return Err("odd two-byte string length".into());
        }
        let units: Vec<u16> = self
            .r
            .bytes(n)?
            .chunks(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        String::from_utf16(&units).map_err(|_| "bad UTF-16 string".into())
    }
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
}
