//! Spike S6: which HPKE wraps the vault keys. Three candidates, two KEMs,
//! one suite (base mode, HKDF-SHA256, ChaCha20-Poly1305):
//!
//!   hpkebench vectors   the published test vectors, on each candidate
//!   hpkebench interop   what one seals, every other opens
//!   hpkebench bench     how long each step takes, and the sizes
//!   hpkebench           all three; `--json FILE` keeps the numbers
//!
//! It exits with an error when a check fails, for the CI.

mod fixed;
mod suites;
mod vectors;

use std::hint::black_box;
use std::time::Instant;

use serde::Serialize;
use suites::Kem;

/// What a vault key wrap would carry: a 32-byte key, bound to what it is.
const INFO: &[u8] = b"openward vault key v1";
const AAD: &[u8] = b"vault 0d8e6b1c-7c5e-4d7a-9a51-3f0e2b6c9a10, generation 1";
const KEY: [u8; 32] = [0x42; 32];

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut what = "all".to_string();
    let mut json = None;
    let mut iters = 2000;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--json" => {
                i += 1;
                json = args.get(i).cloned();
            }
            "--iters" => {
                i += 1;
                iters = args.get(i).and_then(|n| n.parse().ok()).expect("--iters N");
            }
            w @ ("vectors" | "interop" | "bench" | "all") => what = w.into(),
            other => {
                eprintln!("unknown argument {other}");
                std::process::exit(2);
            }
        }
        i += 1;
    }

    let mut report = Report {
        system: format!("{} {}", std::env::consts::OS, std::env::consts::ARCH),
        checks: Vec::new(),
        timings: Vec::new(),
        sizes: Vec::new(),
    };
    if matches!(what.as_str(), "vectors" | "all") {
        report.checks.extend(vectors::run());
    }
    if matches!(what.as_str(), "interop" | "all") {
        report.checks.extend(interop());
    }
    if matches!(what.as_str(), "bench" | "all") {
        report.sizes = sizes();
        report.timings = bench(iters);
    }
    print(&report);
    if let Some(path) = json {
        std::fs::write(&path, serde_json::to_string_pretty(&report).unwrap()).expect("write json");
    }
    if report.checks.iter().any(|c| !c.ok) {
        std::process::exit(1);
    }
}

#[derive(Serialize)]
struct Report {
    system: String,
    checks: Vec<vectors::Check>,
    timings: Vec<Timing>,
    sizes: Vec<Sizes>,
}

/// Every candidate seals for every other's key pair, and a changed byte,
/// `info` or `aad` does not open.
fn interop() -> Vec<vectors::Check> {
    let mut out = Vec::new();
    for kem in Kem::ALL {
        let suites = suites::all(kem);
        for receiver in &suites {
            for sender in &suites {
                let (sk, pk) = receiver.keypair();
                let (enc, ct) = sender.seal(&pk, INFO, AAD, &KEY);
                let opened = receiver.open(&sk, &enc, INFO, AAD, &ct);
                let mut bad = ct.clone();
                bad[0] ^= 1;
                let mut bad_enc = enc.clone();
                bad_enc[enc.len() - 1] ^= 1;
                let refused = receiver.open(&sk, &enc, INFO, AAD, &bad).is_none()
                    && receiver.open(&sk, &enc, b"other info", AAD, &ct).is_none()
                    && receiver.open(&sk, &enc, INFO, b"other aad", &ct).is_none()
                    && receiver.open(&sk, &bad_enc, INFO, AAD, &ct).is_none();
                let ok = opened.as_deref() == Some(&KEY[..]) && refused;
                out.push(vectors::Check {
                    library: receiver.library().into(),
                    what: format!("{} interop: opens from {}", kem.name(), sender.library()),
                    ok,
                    detail: if ok {
                        "opens, and refuses a changed ct, enc, info or aad".into()
                    } else {
                        format!(
                            "opened: {}, refused the changed: {refused}",
                            opened.is_some()
                        )
                    },
                });
            }
        }
    }
    out
}

#[derive(Serialize)]
struct Sizes {
    kem: &'static str,
    public_key: usize,
    private_key: usize,
    enc: usize,
    /// For the 32-byte key.
    ciphertext: usize,
}

fn sizes() -> Vec<Sizes> {
    Kem::ALL
        .into_iter()
        .map(|kem| {
            let s = &suites::all(kem)[0];
            let (sk, pk) = s.keypair();
            let (enc, ct) = s.seal(&pk, INFO, AAD, &KEY);
            Sizes {
                kem: kem.name(),
                public_key: pk.len(),
                private_key: sk.len(),
                enc: enc.len(),
                ciphertext: ct.len(),
            }
        })
        .collect()
}

#[derive(Serialize)]
struct Timing {
    library: &'static str,
    kem: &'static str,
    step: &'static str,
    median_us: f64,
    p95_us: f64,
    iters: usize,
}

fn bench(iters: usize) -> Vec<Timing> {
    let mut out = Vec::new();
    for kem in Kem::ALL {
        for s in suites::all(kem) {
            let (sk, pk) = s.keypair();
            let (enc, ct) = s.seal(&pk, INFO, AAD, &KEY);
            let ikm = [7u8; 32];
            let mut time = |step: &'static str, f: &mut dyn FnMut()| {
                // Warm up, then one sample per call.
                for _ in 0..iters / 10 {
                    f();
                }
                let mut samples: Vec<f64> = (0..iters)
                    .map(|_| {
                        let t = Instant::now();
                        f();
                        t.elapsed().as_secs_f64() * 1e6
                    })
                    .collect();
                samples.sort_by(f64::total_cmp);
                out.push(Timing {
                    library: s.library(),
                    kem: kem.name(),
                    step,
                    median_us: samples[iters / 2],
                    p95_us: samples[iters * 95 / 100],
                    iters,
                });
            };
            time("keypair", &mut || {
                black_box(s.keypair());
            });
            time("derive", &mut || {
                black_box(s.derive(black_box(&ikm)));
            });
            time("seal", &mut || {
                black_box(s.seal(black_box(&pk), INFO, AAD, &KEY));
            });
            time("open", &mut || {
                black_box(s.open(black_box(&sk), &enc, INFO, AAD, &ct));
            });
        }
    }
    out
}

fn print(r: &Report) {
    println!("S6 · HPKE on {}\n", r.system);
    if !r.checks.is_empty() {
        for c in &r.checks {
            let mark = if c.ok { "ok  " } else { "FAIL" };
            println!("{mark} {:28} {:58} {}", c.library, c.what, c.detail);
        }
        let failed = r.checks.iter().filter(|c| !c.ok).count();
        println!("\n{} checks, {failed} failed\n", r.checks.len());
    }
    if !r.sizes.is_empty() {
        println!(
            "{:14} {:>10} {:>11} {:>6} {:>10}",
            "bytes", "public", "private", "enc", "ct (32 B)"
        );
        for s in &r.sizes {
            println!(
                "{:14} {:>10} {:>11} {:>6} {:>10}",
                s.kem, s.public_key, s.private_key, s.enc, s.ciphertext
            );
        }
        println!();
    }
    if !r.timings.is_empty() {
        println!(
            "{:28} {:14} {:8} {:>10} {:>10}",
            "µs", "", "", "median", "p95"
        );
        for t in &r.timings {
            println!(
                "{:28} {:14} {:8} {:>10.1} {:>10.1}",
                t.library, t.kem, t.step, t.median_us, t.p95_us
            );
        }
    }
}
