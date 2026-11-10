//! An item's revisions, and the two merges the spike compares.
//!
//! - **Field clocks** (proposed): every revision carries, for each field,
//!   the clock of the write that last set it. A merge takes, field by
//!   field, the latest. It is a last-writer-wins map, a CRDT: it needs no
//!   history, so a device that comes back after the logs were pruned still
//!   merges right.
//! - **Three-way** (ADR-005 as written): from the common ancestor of the
//!   heads, a field changed on one side only takes that side; changed on
//!   both, the head with the later clock wins. It needs the history back to
//!   that ancestor.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use ciborium::Value;
use serde::Serialize;

use crate::cbor;
use crate::envelope::{Id, Rev};
use crate::fields::{self, Fields, Path};
use crate::hlc::Hlc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub enum Model {
    FieldClocks,
    ThreeWay,
}

impl Model {
    pub const ALL: [Model; 2] = [Model::FieldClocks, Model::ThreeWay];

    pub fn name(self) -> &'static str {
        match self {
            Model::FieldClocks => "field clocks",
            Model::ThreeWay => "three-way",
        }
    }
}

/// A field's value (`None`: unset) and the clock of the write that set it.
#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub clock: Hlc,
    pub value: Option<Value>,
}

impl Entry {
    /// The order of two writes to one field: the later clock; on a tie (two
    /// devices in the same millisecond with the same counter), the greater
    /// value, so that every device picks the same one.
    fn key(&self) -> (Hlc, Vec<u8>) {
        let value = match &self.value {
            None => Vec::new(),
            Some(v) => [&[1u8][..], &cbor::encode(v)].concat(),
        };
        (self.clock, value)
    }
}

pub type Entries = BTreeMap<Path, Entry>;

/// What is set.
pub fn values(entries: &Entries) -> Fields {
    entries
        .iter()
        .filter_map(|(p, e)| Some((p.clone(), e.value.clone()?)))
        .collect()
}

/// The field-clock merge of any number of states.
pub fn by_field_clocks<'a>(states: impl IntoIterator<Item = &'a Entries>) -> Entries {
    let mut out = Entries::new();
    for entries in states {
        for (p, e) in entries {
            match out.get(p) {
                Some(have) if have.key() >= e.key() => {}
                _ => {
                    out.insert(p.clone(), e.clone());
                }
            }
        }
    }
    out
}

/// What goes inside `ct`. The body is the same CBOR as today's `v: 0`.
///
/// - Field clocks: `{hlc, body, base, clocks, unset}`. `base` is the
///   oldest clock; `clocks` has only the fields written after it, and
///   `unset` the fields that a write emptied, with their clocks.
/// - Three-way: `{hlc, body}`.
pub fn plaintext(model: Model, hlc: Hlc, entries: &Entries) -> Vec<u8> {
    let body = Value::Bytes(cbor::encode(&fields::unflatten(&values(entries))));
    let mut out = vec![("hlc", Value::from(hlc.0)), ("body", body)];
    if model == Model::FieldClocks {
        let base = entries.values().map(|e| e.clock).min().unwrap_or(hlc);
        let clocks = |unset: bool| {
            cbor::map(
                entries
                    .iter()
                    .filter(|(_, e)| e.value.is_none() == unset && (unset || e.clock != base))
                    .map(|(p, e)| (Value::Text(p.clone()), Value::from(e.clock.0)))
                    .collect(),
            )
        };
        out.push(("base", Value::from(base.0)));
        out.push(("clocks", clocks(false)));
        out.push(("unset", clocks(true)));
    }
    cbor::encode(&cbor::text_map(out))
}

pub fn read_plaintext(model: Model, bytes: &[u8]) -> Option<(Hlc, Entries)> {
    let value: Value = ciborium::from_reader(bytes).ok()?;
    let map = value.as_map()?;
    let hlc = Hlc(cbor::uint(cbor::get(map, "hlc")?)?);
    let body: Value = ciborium::from_reader(&cbor::get(map, "body")?.as_bytes()?[..]).ok()?;
    let present = fields::flatten(&body)?;
    let mut entries = Entries::new();
    match model {
        Model::ThreeWay => {
            for (p, v) in present {
                entries.insert(
                    p,
                    Entry {
                        clock: hlc,
                        value: Some(v),
                    },
                );
            }
        }
        Model::FieldClocks => {
            let base = Hlc(cbor::uint(cbor::get(map, "base")?)?);
            let clocks = |key| -> Option<HashMap<String, Hlc>> {
                cbor::get(map, key)?
                    .as_map()?
                    .iter()
                    .map(|(k, v)| Some((k.as_text()?.to_string(), Hlc(cbor::uint(v)?))))
                    .collect()
            };
            let written = clocks("clocks")?;
            for (p, v) in present {
                let clock = written.get(&p).copied().unwrap_or(base);
                entries.insert(
                    p,
                    Entry {
                        clock,
                        value: Some(v),
                    },
                );
            }
            for (p, clock) in clocks("unset")? {
                entries.insert(p, Entry { clock, value: None });
            }
        }
    }
    Some((hlc, entries))
}

pub struct Revision {
    pub rev: Rev,
    pub parents: Vec<Rev>,
    pub device: Id,
    pub hlc: Hlc,
    pub entries: Entries,
    /// The envelope, as shipped.
    pub bytes: Vec<u8>,
}

/// The heads of an item and what they merge to.
pub struct Merged {
    pub entries: Entries,
    /// The heads, which a new revision names as its parents.
    pub parents: Vec<Rev>,
    pub hlc: Hlc,
}

#[derive(Default)]
pub struct ItemDag {
    revs: HashMap<Rev, Revision>,
    /// Who names each revision as a parent, including revisions not here
    /// (not read yet, or pruned).
    children: HashMap<Rev, Vec<Rev>>,
    heads: BTreeSet<Rev>,
}

/// One side of a three-way merge: a head, or heads already merged.
struct Side {
    entries: Entries,
    ancestors: HashSet<Rev>,
    hlc: Hlc,
    rev: Rev,
}

impl ItemDag {
    pub fn contains(&self, rev: &Rev) -> bool {
        self.revs.contains_key(rev)
    }

    pub fn len(&self) -> usize {
        self.revs.len()
    }

    pub fn is_empty(&self) -> bool {
        self.revs.is_empty()
    }

    /// Adds a revision, in any order: one that arrives before its parents
    /// is a head until they come, and a parent that arrives after its
    /// child is not a head.
    pub fn insert(&mut self, r: Revision) -> bool {
        if self.revs.contains_key(&r.rev) {
            return false;
        }
        for p in &r.parents {
            self.children.entry(*p).or_default().push(r.rev);
            self.heads.remove(p);
        }
        if !self.children.contains_key(&r.rev) {
            self.heads.insert(r.rev);
        }
        self.revs.insert(r.rev, r);
        true
    }

    /// In a fixed order: by clock, then by id.
    pub fn heads(&self) -> Vec<&Revision> {
        let mut heads: Vec<&Revision> = self.heads.iter().map(|h| &self.revs[h]).collect();
        heads.sort_by_key(|r| (r.hlc, r.rev));
        heads
    }

    pub fn merged(&self, model: Model) -> Merged {
        let heads = self.heads();
        let parents: Vec<Rev> = heads.iter().map(|r| r.rev).collect();
        let hlc = heads.iter().map(|r| r.hlc).max().unwrap_or_default();
        let entries = match (model, heads.as_slice()) {
            (_, []) => Entries::new(),
            (_, [one]) => one.entries.clone(),
            (Model::FieldClocks, _) => by_field_clocks(heads.iter().map(|r| &r.entries)),
            (Model::ThreeWay, _) => self.three_way(&parents).entries,
        };
        Merged {
            entries,
            parents,
            hlc,
        }
    }

    /// The revisions here that `from` descends from, `from` included.
    fn ancestors(&self, from: &[Rev]) -> HashSet<Rev> {
        let mut seen = HashSet::new();
        let mut stack = from.to_vec();
        while let Some(r) = stack.pop() {
            if let Some(rev) = self.revs.get(&r)
                && seen.insert(r)
            {
                stack.extend(&rev.parents);
            }
        }
        seen
    }

    fn three_way(&self, heads: &[Rev]) -> Side {
        let mut sides: Vec<Side> = heads
            .iter()
            .filter_map(|h| self.revs.get(h))
            .map(|r| Side {
                entries: r.entries.clone(),
                ancestors: self.ancestors(&[r.rev]),
                hlc: r.hlc,
                rev: r.rev,
            })
            .collect();
        sides.sort_by_key(|s| (s.hlc, s.rev));
        let mut sides = sides.into_iter();
        let first = sides.next().expect("at least one head");
        sides.fold(first, |x, y| self.merge_two(x, y))
    }

    fn merge_two(&self, x: Side, y: Side) -> Side {
        let common: HashSet<Rev> = x.ancestors.intersection(&y.ancestors).copied().collect();
        // The lowest common ancestors: no child of theirs is common too.
        let mut lowest: Vec<Rev> = common
            .iter()
            .filter(|c| {
                !self
                    .children
                    .get(*c)
                    .is_some_and(|kids| kids.iter().any(|k| common.contains(k)))
            })
            .copied()
            .collect();
        lowest.sort();
        // Several (criss-cross merges): their own merge is the base, as in
        // Git's recursive strategy. None (the history is not here): every
        // difference is a conflict.
        let base = match lowest.as_slice() {
            [] => Entries::new(),
            [one] => self.revs[one].entries.clone(),
            many => self.three_way(many).entries,
        };
        let x_later = (x.hlc, x.rev) > (y.hlc, y.rev);
        let paths: BTreeSet<&Path> = x
            .entries
            .keys()
            .chain(y.entries.keys())
            .chain(base.keys())
            .collect();
        let mut entries = Entries::new();
        for p in paths {
            let value = |s: &Entries| s.get(p).and_then(|e| e.value.clone());
            let (vx, vy, vb) = (value(&x.entries), value(&y.entries), value(&base));
            let take_x = if vx == vy || vy == vb {
                true
            } else if vx == vb {
                false
            } else {
                x_later
            };
            let side = if take_x { &x.entries } else { &y.entries };
            if let Some(e) = side.get(p) {
                entries.insert(p.clone(), e.clone());
            }
        }
        Side {
            entries,
            ancestors: x.ancestors.union(&y.ancestors).copied().collect(),
            hlc: x.hlc.max(y.hlc),
            rev: x.rev.max(y.rev),
        }
    }

    /// The writes that lost to a concurrent write to the same field, for
    /// the notice in the UI (field clocks): an entry of a head that is not
    /// the winning one, and that the winning head's history never had.
    pub fn lost(&self) -> Vec<(Path, Entry)> {
        let heads = self.heads();
        if heads.len() < 2 {
            return Vec::new();
        }
        let winner = by_field_clocks(heads.iter().map(|r| &r.entries));
        let mut out = Vec::new();
        for (p, w) in &winner {
            let Some(from) = heads.iter().find(|h| h.entries.get(p) == Some(w)) else {
                continue;
            };
            let seen: Vec<&Entry> = self
                .ancestors(&[from.rev])
                .iter()
                .filter_map(|r| self.revs[r].entries.get(p))
                .collect();
            for h in &heads {
                if let Some(e) = h.entries.get(p)
                    && e != w
                    && !seen.contains(&e)
                    && !out.iter().any(|(q, f)| q == p && f == e)
                {
                    out.push((p.clone(), e.clone()));
                }
            }
        }
        out
    }
}
