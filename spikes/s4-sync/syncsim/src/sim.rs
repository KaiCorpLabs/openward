//! Devices simulated in memory. Each one writes only to its own log, in a
//! storage every device reads (the folder, S3 or the relay of v0.5), and
//! merges what it reads. Logs are read in pieces and in any order, as a
//! synced folder delivers them.
//!
//! Beside the format, the simulation keeps its own record of what each
//! device had seen (a version vector per revision, never shipped). That is
//! the oracle: a write that another device overwrote after seeing it must
//! lose, and a write that no other write saw must not lose to an older one.

use std::collections::{BTreeMap, HashMap};

use ciborium::Value;
use ed25519_dalek::{SigningKey, VerifyingKey};
use serde::Serialize;

use crate::dag::{self, Entry, ItemDag, Model, Revision};
use crate::envelope::{Envelope, Header, Id, Rev};
use crate::fields::{self, Fields, Path};
use crate::hlc::Clock;

/// The fields the simulation writes: two flat, two nested, and the trash.
pub const PATHS: [&str; 5] = [
    "label",
    "port",
    "settings\u{1f}user",
    "settings\u{1f}jump",
    "deleted",
];

#[derive(Clone, Debug)]
pub enum Op {
    /// Sets a field (`None`: unsets it).
    Write {
        device: usize,
        item: usize,
        path: usize,
        value: Option<u8>,
    },
    /// Uploads what the device wrote since its last push.
    Push { device: usize },
    /// Reads up to `max` new revisions of another device's log.
    Pull {
        reader: usize,
        writer: usize,
        max: usize,
    },
    /// Wall time goes on.
    Wait { ms: u32 },
    /// The device reads everything and leaves a snapshot of its heads, and
    /// the storage drops the logs up to there, as ADR-005's retention would
    /// while a device is away.
    Compact { device: usize },
}

/// Writes seen, per device.
pub type Vc = Vec<u64>;

struct Device {
    id: Id,
    key: SigningKey,
    clock: Clock,
    skew_ms: i64,
    items: BTreeMap<Id, ItemDag>,
    outbox: Vec<Vec<u8>>,
    /// How far it read each device's log.
    cursors: Vec<usize>,
    /// The last snapshot it loaded.
    epoch: u32,
    /// The oracle's record, per item: a revision of one item says nothing
    /// about another.
    seen: BTreeMap<Id, Vc>,
    seq: u64,
}

/// One field set by one revision, for the oracle.
struct Write {
    item: Id,
    path: Path,
    value: Option<Value>,
    author: usize,
    seq: u64,
    /// What the author had seen, this write included.
    vc: Vc,
}

#[derive(Clone, Debug, Default, Serialize)]
pub struct Stats {
    pub writes: usize,
    pub revisions: usize,
    pub ingested: usize,
    pub envelope_bytes: usize,
    pub max_heads: usize,
    pub compactions: usize,
    pub snapshot_loads: usize,
    /// Timestamps a device did not follow, too far ahead of its clock.
    pub clocks_not_followed: usize,
}

#[derive(Debug, Serialize)]
pub struct Outcome {
    /// Every device has the same values for every item.
    pub converged: bool,
    /// Writes the oracle says should have survived and did not.
    pub violations: Vec<String>,
    /// Concurrent writes to one field that lost (field clocks), as the UI
    /// would list them.
    pub lost: usize,
}

impl Outcome {
    pub fn ok(&self) -> bool {
        self.converged && self.violations.is_empty()
    }
}

pub struct Sim {
    pub model: Model,
    vault: Id,
    key: [u8; 32],
    devices: Vec<Device>,
    registry: HashMap<Id, VerifyingKey>,
    /// The storage: each device's log, the first entry of each still there
    /// after pruning, and the snapshot that covers what was pruned.
    logs: Vec<Vec<Vec<u8>>>,
    pruned: Vec<usize>,
    snapshot: Vec<Vec<u8>>,
    epoch: u32,
    now_ms: u64,
    items: Vec<Id>,
    writes: Vec<Write>,
    vcs: HashMap<Rev, Vc>,
    pub stats: Stats,
}

impl Sim {
    /// `skews`: how far each device's wall clock is from true time.
    pub fn new(model: Model, skews: &[i64], items: usize, max_ahead_ms: u64) -> Self {
        let n = skews.len();
        let devices: Vec<Device> = skews
            .iter()
            .enumerate()
            .map(|(i, &skew_ms)| Device {
                id: [i as u8 + 1; 16],
                key: SigningKey::from_bytes(&[i as u8 + 100; 32]),
                clock: Clock::new(max_ahead_ms),
                skew_ms,
                items: BTreeMap::new(),
                outbox: Vec::new(),
                cursors: vec![0; n],
                epoch: 0,
                seen: BTreeMap::new(),
                seq: 0,
            })
            .collect();
        let registry = devices
            .iter()
            .map(|d| (d.id, d.key.verifying_key()))
            .collect();
        let mut sim = Self {
            model,
            vault: [0xaa; 16],
            key: [42; 32],
            devices,
            registry,
            logs: vec![Vec::new(); n],
            pruned: vec![0; n],
            snapshot: Vec::new(),
            epoch: 0,
            now_ms: 1_800_000_000_000,
            items: (0..items)
                .map(|i| {
                    let mut id = [0xbb; 16];
                    id[..8].copy_from_slice(&(i as u64).to_be_bytes());
                    id
                })
                .collect(),
            writes: Vec::new(),
            vcs: HashMap::new(),
            stats: Stats::default(),
        };
        // The first device creates the items, and everyone reads them.
        for item in sim.items.clone() {
            let all: Vec<(Path, Option<Value>)> = PATHS
                .iter()
                .map(|p| (p.to_string(), Some(Value::from(0))))
                .collect();
            sim.write(0, item, &all);
        }
        sim.settle();
        sim
    }

    pub fn devices(&self) -> usize {
        self.devices.len()
    }

    fn wall(&self, d: usize) -> u64 {
        self.now_ms.saturating_add_signed(self.devices[d].skew_ms)
    }

    pub fn apply(&mut self, op: &Op) {
        match *op {
            Op::Write {
                device,
                item,
                path,
                value,
            } => {
                let item = self.items[item % self.items.len()];
                let edit = (PATHS[path].to_string(), value.map(Value::from));
                self.write(device, item, &[edit]);
            }
            Op::Push { device } => self.push(device),
            Op::Pull {
                reader,
                writer,
                max,
            } => self.pull(reader, writer, max),
            Op::Wait { ms } => self.now_ms += u64::from(ms),
            Op::Compact { device } => self.compact(device),
        }
    }

    pub fn write(&mut self, d: usize, item: Id, edits: &[(Path, Option<Value>)]) {
        let now = self.wall(d);
        let model = self.model;
        let dev = &mut self.devices[d];
        let dag = dev.items.entry(item).or_default();
        let merged = dag.merged(model);
        let tick = dev.clock.tick(now);
        let mut entries = merged.entries;
        // After its parents, and each field after the write it replaces:
        // a device whose clock is behind, or that did not follow a clock
        // far ahead, still overwrites what it saw.
        let mut hlc = tick.max(merged.hlc.next());
        for (p, value) in edits {
            let clock = entries.get(p).map_or(tick, |e| tick.max(e.clock.next()));
            hlc = hlc.max(clock);
            entries.insert(
                p.clone(),
                Entry {
                    clock,
                    value: value.clone(),
                },
            );
        }
        dev.clock.bump(hlc);
        let plaintext = dag::plaintext(model, hlc, &entries);
        let header = Header {
            vault: self.vault,
            item,
            device: dev.id,
            key_gen: 1,
            parents: merged.parents,
        };
        let env = Envelope::seal(header, &plaintext, &self.key, &dev.key);
        let bytes = env.to_bytes();
        let rev = env.rev();
        // Stored as any other device will read it.
        let (_, entries) = dag::read_plaintext(model, &plaintext).expect("own plaintext");
        dag.insert(Revision {
            rev,
            parents: env.header.parents,
            device: dev.id,
            hlc,
            entries,
            bytes: bytes.clone(),
        });
        self.stats.max_heads = self.stats.max_heads.max(dag.heads().len());
        dev.seq += 1;
        let n = dev.cursors.len();
        let vc = dev.seen.entry(item).or_insert_with(|| vec![0; n]);
        vc[d] = dev.seq;
        for (p, value) in edits {
            self.writes.push(Write {
                item,
                path: p.clone(),
                value: value.clone(),
                author: d,
                seq: dev.seq,
                vc: vc.clone(),
            });
        }
        self.vcs.insert(rev, vc.clone());
        self.stats.writes += edits.len();
        self.stats.revisions += 1;
        self.stats.envelope_bytes += bytes.len();
        dev.outbox.push(bytes);
    }

    fn push(&mut self, d: usize) {
        let out = std::mem::take(&mut self.devices[d].outbox);
        self.logs[d].extend(out);
    }

    fn pull(&mut self, r: usize, w: usize, max: usize) {
        if r == w {
            return;
        }
        if self.devices[r].cursors[w] < self.pruned[w] && self.devices[r].epoch < self.epoch {
            self.load_snapshot(r);
        }
        let start = self.devices[r].cursors[w].max(self.pruned[w]);
        let end = self.logs[w].len().min(start.saturating_add(max));
        for i in start..end {
            let bytes = self.logs[w][i].clone();
            self.ingest(r, &bytes);
        }
        self.devices[r].cursors[w] = end.max(self.devices[r].cursors[w]);
    }

    fn load_snapshot(&mut self, r: usize) {
        for bytes in self.snapshot.clone() {
            self.ingest(r, &bytes);
        }
        let dev = &mut self.devices[r];
        dev.epoch = self.epoch;
        for (c, p) in dev.cursors.iter_mut().zip(&self.pruned) {
            *c = (*c).max(*p);
        }
        self.stats.snapshot_loads += 1;
    }

    fn ingest(&mut self, r: usize, bytes: &[u8]) {
        let env = Envelope::from_bytes(bytes).expect("a well-formed envelope");
        env.verify(&self.registry[&env.header.device])
            .expect("a signature from a known device");
        assert_eq!(env.header.vault, self.vault);
        let rev = env.rev();
        let now = self.wall(r);
        let dev = &mut self.devices[r];
        let dag = dev.items.entry(env.header.item).or_default();
        if dag.contains(&rev) {
            return;
        }
        let plaintext = env.open(&self.key).expect("opens with the vault key");
        let (hlc, entries) = dag::read_plaintext(self.model, &plaintext).expect("plaintext");
        if !dev.clock.observe(hlc, now) {
            self.stats.clocks_not_followed += 1;
        }
        dag.insert(Revision {
            rev,
            parents: env.header.parents.clone(),
            device: env.header.device,
            hlc,
            entries,
            bytes: bytes.to_vec(),
        });
        self.stats.max_heads = self.stats.max_heads.max(dag.heads().len());
        let n = dev.cursors.len();
        let vc = dev
            .seen
            .entry(env.header.item)
            .or_insert_with(|| vec![0; n]);
        for (mine, seen) in vc.iter_mut().zip(&self.vcs[&rev]) {
            *mine = (*mine).max(*seen);
        }
        self.stats.ingested += 1;
    }

    fn compact(&mut self, c: usize) {
        self.push(c);
        for w in 0..self.devices.len() {
            self.pull(c, w, usize::MAX);
        }
        self.snapshot = self.devices[c]
            .items
            .values()
            .flat_map(|dag| dag.heads().into_iter().map(|r| r.bytes.clone()))
            .collect();
        self.epoch += 1;
        self.devices[c].epoch = self.epoch;
        for (p, log) in self.pruned.iter_mut().zip(&self.logs) {
            *p = log.len();
        }
        self.stats.compactions += 1;
    }

    /// Everyone pushes, then everyone reads everything.
    pub fn settle(&mut self) {
        let n = self.devices.len();
        for d in 0..n {
            self.push(d);
        }
        for r in 0..n {
            for w in 0..n {
                self.pull(r, w, usize::MAX);
            }
        }
    }

    /// What one device shows for each item.
    pub fn state(&self, d: usize) -> BTreeMap<Id, Fields> {
        self.devices[d]
            .items
            .iter()
            .map(|(id, dag)| (*id, dag::values(&dag.merged(self.model).entries)))
            .collect()
    }

    pub fn revisions(&self, d: usize) -> usize {
        self.devices[d].items.values().map(ItemDag::len).sum()
    }

    /// After [`Sim::settle`]: the same state everywhere, and every write
    /// that should survive did.
    pub fn check(&self) -> Outcome {
        let states: Vec<_> = (0..self.devices.len()).map(|d| self.state(d)).collect();
        let converged = states.windows(2).all(|w| w[0] == w[1]);
        let mut groups: BTreeMap<(Id, &Path), Vec<&Write>> = BTreeMap::new();
        for w in &self.writes {
            groups.entry((w.item, &w.path)).or_default().push(w);
        }
        let mut violations = Vec::new();
        for ((item, path), writes) in &groups {
            // The writes no other write to this field had seen.
            let last: Vec<&Write> = writes
                .iter()
                .filter(|w| {
                    !writes
                        .iter()
                        .any(|o| (o.author, o.seq) != (w.author, w.seq) && o.vc[w.author] >= w.seq)
                })
                .copied()
                .collect();
            for (d, state) in states.iter().enumerate() {
                let has = state.get(item).and_then(|f| f.get(*path)).cloned();
                if !last.iter().any(|w| w.value == has) {
                    let want: Vec<String> = last.iter().map(|w| show(&w.value)).collect();
                    violations.push(format!(
                        "device {d}, item {}, {}: has {}, the last writes were {}",
                        item[7],
                        fields::show(path),
                        show(&has),
                        want.join(" or ")
                    ));
                }
            }
        }
        let lost = match self.model {
            Model::FieldClocks => self.devices[0].items.values().map(|d| d.lost().len()).sum(),
            Model::ThreeWay => 0,
        };
        Outcome {
            converged,
            violations,
            lost,
        }
    }
}

fn show(v: &Option<Value>) -> String {
    match v {
        None => "unset".into(),
        Some(Value::Integer(i)) => i128::from(*i).to_string(),
        Some(other) => format!("{other:?}"),
    }
}
