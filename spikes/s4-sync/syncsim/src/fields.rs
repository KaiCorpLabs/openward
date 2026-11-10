//! An item's body as a flat map of paths to values, so that a merge can go
//! field by field without knowing the item's type, fields that a newer
//! version added included. Nested maps become paths (`settings` › `port`);
//! arrays and scalars are values, and so is an empty map, so that it
//! survives. The parts of a path are joined with U+001F, which no key has:
//! keys can have dots (`settings` › `env` › `A.B`).

use std::collections::BTreeMap;

use ciborium::Value;

use crate::cbor;

pub const SEP: char = '\u{1f}';

pub type Path = String;
pub type Fields = BTreeMap<Path, Value>;

/// The parts of a path, for people.
pub fn show(path: &str) -> String {
    path.replace(SEP, ".")
}

pub fn join(parts: &[&str]) -> Path {
    parts.join(&SEP.to_string())
}

/// The leaves of a body, which is a map with text keys.
pub fn flatten(body: &Value) -> Option<Fields> {
    let mut out = Fields::new();
    walk(body.as_map()?, "", &mut out)?;
    Some(out)
}

fn walk(map: &[(Value, Value)], prefix: &str, out: &mut Fields) -> Option<()> {
    for (k, v) in map {
        let k = k.as_text()?;
        if k.contains(SEP) {
            return None;
        }
        let path = if prefix.is_empty() {
            k.to_string()
        } else {
            format!("{prefix}{SEP}{k}")
        };
        match v {
            Value::Map(inner) if !inner.is_empty() => walk(inner, &path, out)?,
            _ => {
                out.insert(path, v.clone());
            }
        }
    }
    Some(())
}

/// The body again, in deterministic order. When a path has a value and
/// also paths below it (a field that one device emptied and another
/// filled), what is below wins.
pub fn unflatten(fields: &Fields) -> Value {
    #[derive(Default)]
    struct Node {
        value: Option<Value>,
        below: BTreeMap<String, Node>,
    }
    let mut root = Node::default();
    for (path, value) in fields {
        let mut node = &mut root;
        for part in path.split(SEP) {
            node = node.below.entry(part.to_string()).or_default();
        }
        node.value = Some(value.clone());
    }
    fn build(node: &Node) -> Value {
        cbor::map(
            node.below
                .iter()
                .map(|(k, n)| {
                    let v = if n.below.is_empty() {
                        n.value.clone().unwrap_or(Value::Null)
                    } else {
                        build(n)
                    };
                    (Value::Text(k.clone()), v)
                })
                .collect(),
        )
    }
    build(&root)
}

#[cfg(test)]
mod tests {
    use super::*;
    use openward_proto::{Body, Data, Extra, Host, Jump, Route, Settings};

    fn body() -> Body {
        let mut env = BTreeMap::new();
        env.insert("LANG.X".to_string(), "es".to_string());
        Body {
            created: 1,
            modified: 2,
            data: Data::Host(Host {
                label: "web".into(),
                address: "web.example.com".into(),
                tags: vec!["prod".into(), "eu".into()],
                settings: Settings {
                    port: Some(2222),
                    env: Some(env),
                    route: Some(Route::Jump(vec![Jump::Address {
                        host: "bastion".into(),
                        user: Some("ops".into()),
                        port: None,
                        extra: Extra::new(),
                    }])),
                    ..Settings::default()
                },
                ..Host::default()
            }),
        }
    }

    #[test]
    fn a_real_body_goes_to_paths_and_back() {
        let b = body();
        let value: Value = ciborium::from_reader(&b.to_cbor()[..]).unwrap();
        let fields = flatten(&value).unwrap();
        assert!(fields.contains_key(&join(&["settings", "port"])));
        assert!(fields.contains_key(&join(&["settings", "env", "LANG.X"])));
        let back = cbor::encode(&unflatten(&fields));
        assert_eq!(Body::from_cbor(&back).unwrap(), b);
    }

    #[test]
    fn what_is_below_a_path_wins_over_its_value() {
        let mut f = Fields::new();
        f.insert("settings".into(), Value::Map(vec![]));
        f.insert(join(&["settings", "port"]), Value::from(22));
        let v = unflatten(&f);
        assert_eq!(flatten(&v).unwrap().len(), 1);
    }
}
