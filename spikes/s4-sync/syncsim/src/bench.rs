//! The numbers: what the v1 envelope weighs, how long opening 10,000 items
//! takes, and long runs of the simulation.

use std::hint::black_box;
use std::time::Instant;

use ciborium::Value;
use ed25519_dalek::{Signature, SigningKey};
use openward_proto::{
    Body, Data, Environment, EnvironmentMark, Extra, Host, Jump, Route, Settings, System,
    SystemSource, envelope as v0,
};
use rand::rngs::StdRng;
use rand::{RngExt, SeedableRng};
use serde::Serialize;

use crate::cbor;
use crate::dag::{self, Entries, Entry, Model};
use crate::envelope::{Envelope, Header};
use crate::fields;
use crate::hlc::Hlc;
use crate::sim::{Op, PATHS, Sim};

/// A host like the ones people have: most with a user and a system, some
/// with tags, a port, a jump or an environment.
pub fn host(i: usize) -> Body {
    let mut settings = Settings::default();
    if i.is_multiple_of(2) {
        settings.user = Some("deploy".into());
    }
    if i.is_multiple_of(5) {
        settings.port = Some(2222);
    }
    if i.is_multiple_of(7) {
        settings.route = Some(Route::Jump(vec![Jump::Address {
            host: "bastion.example.com".into(),
            user: Some("ops".into()),
            port: None,
            extra: Extra::new(),
        }]));
    }
    if i.is_multiple_of(4) {
        settings.environment = Some(Environment::Mark(EnvironmentMark {
            name: "Producción".into(),
            short: "prod".into(),
            color: "red".into(),
            extra: Extra::new(),
        }));
    }
    Body {
        created: 1_800_000_000_000 + i as i64,
        modified: 1_800_000_000_000 + i as i64,
        data: Data::Host(Host {
            label: format!("web-{i:05}"),
            address: format!("web-{i:05}.eu-west-1.example.com"),
            tags: match i % 3 {
                0 => vec!["prod".into(), "eu".into()],
                1 => vec!["staging".into()],
                _ => Vec::new(),
            },
            settings,
            system: (!i.is_multiple_of(10)).then(|| System {
                code: "deb".into(),
                name: "Debian GNU/Linux 12 (bookworm)".into(),
                source: SystemSource::Banner,
                evidence: String::new(),
                extra: Extra::new(),
            }),
            ..Host::default()
        }),
    }
}

fn entries(body: &Body, clock: Hlc) -> Entries {
    let value: Value = ciborium::from_reader(&body.to_cbor()[..]).expect("a body");
    fields::flatten(&value)
        .expect("a map")
        .into_iter()
        .map(|(p, v)| {
            (
                p,
                Entry {
                    clock,
                    value: Some(v),
                },
            )
        })
        .collect()
}

const VAULT_KEY: [u8; 32] = [42; 32];

fn header(i: usize, parents: usize) -> Header {
    let mut item = [0u8; 16];
    item[..8].copy_from_slice(&(i as u64).to_be_bytes());
    Header {
        vault: [0xaa; 16],
        item,
        device: [1; 16],
        key_gen: 1,
        parents: (0..parents).map(|p| [p as u8 + 1; 32]).collect(),
    }
}

#[derive(Debug, Serialize)]
pub struct Sizes {
    /// The body's CBOR, as `openward-proto` writes it.
    pub body: usize,
    pub v0: usize,
    pub v1_three_way: usize,
    pub v1_field_clocks: usize,
    /// After three fields were edited at other times.
    pub v1_field_clocks_edited: usize,
    /// A merge: two parents.
    pub v1_two_parents: usize,
}

pub fn sizes() -> Sizes {
    let body = host(14);
    let key = SigningKey::from_bytes(&[100; 32]);
    let clock = Hlc::at(1_800_000_000_000);
    let new = entries(&body, clock);
    let mut edited = new.clone();
    let user = fields::join(&["settings", "user"]);
    for (n, p) in ["label", "address", user.as_str()].iter().enumerate() {
        edited.get_mut(*p).expect("field").clock = Hlc::at(1_800_000_100_000 + n as u64);
    }
    let seal = |model, e: &Entries, parents| {
        let pt = dag::plaintext(model, clock, e);
        Envelope::seal(header(14, parents), &pt, &VAULT_KEY, &key)
            .to_bytes()
            .len()
    };
    Sizes {
        body: body.to_cbor().len(),
        v0: v0::seal_plain(&body).len(),
        v1_three_way: seal(Model::ThreeWay, &new, 1),
        v1_field_clocks: seal(Model::FieldClocks, &new, 1),
        v1_field_clocks_edited: seal(Model::FieldClocks, &edited, 1),
        v1_two_parents: seal(Model::FieldClocks, &edited, 2),
    }
}

#[derive(Debug, Serialize)]
pub struct Unlock {
    pub items: usize,
    pub v0_bytes: usize,
    pub v1_bytes: usize,
    /// Best of five, in milliseconds.
    pub v0_ms: f64,
    /// Decode (canonical), decrypt and decode the body.
    pub v1_ms: f64,
    /// The same without the canonical check, done when it came in.
    pub v1_stored_ms: f64,
    /// The same, and each signature checked.
    pub v1_verify_ms: f64,
    /// The same, with the signatures checked in one batch.
    pub v1_batch_verify_ms: f64,
}

/// The body out of a v1 plaintext: unlocking needs nothing else.
fn body_of(plaintext: &[u8]) -> Body {
    let value: Value = ciborium::from_reader(plaintext).expect("plaintext");
    let body = cbor::get(value.as_map().expect("map"), "body")
        .and_then(Value::as_bytes)
        .expect("body");
    Body::from_cbor(body).expect("a body")
}

fn best_of_five(mut f: impl FnMut()) -> f64 {
    (0..5)
        .map(|_| {
            let t = Instant::now();
            f();
            t.elapsed().as_secs_f64() * 1e3
        })
        .fold(f64::INFINITY, f64::min)
}

pub fn unlock(items: usize) -> Unlock {
    let key = SigningKey::from_bytes(&[100; 32]);
    let vk = key.verifying_key();
    let clock = Hlc::at(1_800_000_000_000);
    let bodies: Vec<Body> = (0..items).map(host).collect();
    let v0s: Vec<Vec<u8>> = bodies.iter().map(v0::seal_plain).collect();
    let v1s: Vec<Vec<u8>> = bodies
        .iter()
        .enumerate()
        .map(|(i, b)| {
            let pt = dag::plaintext(Model::FieldClocks, clock, &entries(b, clock));
            Envelope::seal(header(i, 1), &pt, &VAULT_KEY, &key).to_bytes()
        })
        .collect();
    let open = |bytes: &[u8]| {
        let env = Envelope::from_bytes(bytes).expect("envelope");
        let body = body_of(&env.open(&VAULT_KEY).expect("opens"));
        (env, body)
    };
    Unlock {
        items,
        v0_bytes: v0s.iter().map(Vec::len).sum(),
        v1_bytes: v1s.iter().map(Vec::len).sum(),
        v0_ms: best_of_five(|| {
            for b in &v0s {
                black_box(v0::open(b).expect("v0"));
            }
        }),
        v1_ms: best_of_five(|| {
            for b in &v1s {
                black_box(open(b));
            }
        }),
        v1_stored_ms: best_of_five(|| {
            for b in &v1s {
                let env = Envelope::from_stored(b).expect("envelope");
                black_box(body_of(&env.open(&VAULT_KEY).expect("opens")));
            }
        }),
        v1_verify_ms: best_of_five(|| {
            for b in &v1s {
                let (env, body) = open(b);
                env.verify(&vk).expect("signed");
                black_box(body);
            }
        }),
        v1_batch_verify_ms: best_of_five(|| {
            let opened: Vec<_> = v1s.iter().map(|b| open(b)).collect();
            let messages: Vec<Vec<u8>> = opened.iter().map(|(e, _)| e.signed_message()).collect();
            let refs: Vec<&[u8]> = messages.iter().map(Vec::as_slice).collect();
            let sigs: Vec<Signature> = opened
                .iter()
                .map(|(e, _)| Signature::from_bytes(&e.sig))
                .collect();
            let keys = vec![vk; opened.len()];
            ed25519_dalek::verify_batch(&refs, &sigs, &keys).expect("signed");
            black_box(opened);
        }),
    }
}

#[derive(Debug, Serialize)]
pub struct Run {
    pub model: &'static str,
    pub items: usize,
    pub writes: usize,
    pub compactions: usize,
    pub ms: f64,
    pub us_per_write: f64,
    pub revisions_per_device: usize,
    pub envelope_bytes: usize,
    pub max_heads: usize,
    pub lost: usize,
    pub snapshot_loads: usize,
    pub clocks_not_followed: usize,
    pub converged: bool,
    pub violations: usize,
    pub first_violation: Option<String>,
}

/// Three devices (one 40 s ahead, one 25 s behind) writing at random,
/// pushing and reading in pieces, until `writes`; then everyone reads
/// everything and the oracle checks.
pub fn run(model: Model, items: usize, writes: usize, compactions: usize, seed: u64) -> Run {
    let mut rng = StdRng::seed_from_u64(seed);
    let mut sim = Sim::new(model, &[0, 40_000, -25_000], items, 60_000);
    let n = sim.devices();
    let every = writes / (compactions + 1);
    let t = Instant::now();
    let mut done = 0;
    while done < writes {
        let op = match rng.random_range(0..10) {
            0..=4 => {
                done += 1;
                Op::Write {
                    device: rng.random_range(0..n),
                    item: rng.random_range(0..items),
                    path: rng.random_range(0..PATHS.len()),
                    value: (rng.random_range(0..8) != 0).then(|| rng.random_range(0..16)),
                }
            }
            5 | 6 => Op::Push {
                device: rng.random_range(0..n),
            },
            7 | 8 => Op::Pull {
                reader: rng.random_range(0..n),
                writer: rng.random_range(0..n),
                max: rng.random_range(1..40),
            },
            _ => Op::Wait {
                ms: rng.random_range(0..3000),
            },
        };
        sim.apply(&op);
        if compactions > 0 && matches!(op, Op::Write { .. }) && done % every == 0 && done < writes {
            sim.apply(&Op::Compact {
                device: rng.random_range(0..n),
            });
        }
    }
    sim.settle();
    let ms = t.elapsed().as_secs_f64() * 1e3;
    let outcome = sim.check();
    Run {
        model: model.name(),
        items,
        writes,
        compactions: sim.stats.compactions,
        ms,
        us_per_write: ms * 1e3 / writes as f64,
        revisions_per_device: sim.revisions(0),
        envelope_bytes: sim.stats.envelope_bytes,
        max_heads: sim.stats.max_heads,
        lost: outcome.lost,
        snapshot_loads: sim.stats.snapshot_loads,
        clocks_not_followed: sim.stats.clocks_not_followed,
        converged: outcome.converged,
        violations: outcome.violations.len(),
        first_violation: outcome.violations.first().cloned(),
    }
}
