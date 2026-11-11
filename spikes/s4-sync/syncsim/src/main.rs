//! Spike S4, part 1: the v1 envelope and the merge, in numbers.
//!
//!   syncsim sizes    what a v1 envelope weighs next to today's v0
//!   syncsim unlock   opening 10,000 hosts, with and without signatures
//!   syncsim runs     3 devices × 10,000 writes, both merges, with and
//!                    without pruned logs; the oracle checks every write
//!   syncsim          all three; `--json FILE` keeps the numbers
//!
//! It exits with an error when a field-clock run does not converge or loses
//! a write: that is the merge proposed. The three-way runs are the
//! comparison, and their failures are a result.

use serde::Serialize;
use syncsim::bench::{self, Run, Sizes, Unlock};
use syncsim::dag::Model;

#[derive(Serialize)]
struct Report {
    system: String,
    sizes: Option<Sizes>,
    unlock: Option<Unlock>,
    runs: Vec<Run>,
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut what = "all".to_string();
    let mut json = None;
    let mut writes = 10_000;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--json" => {
                i += 1;
                json = args.get(i).cloned();
            }
            "--writes" => {
                i += 1;
                writes = args
                    .get(i)
                    .and_then(|n| n.parse().ok())
                    .expect("--writes N");
            }
            w @ ("sizes" | "unlock" | "runs" | "all") => what = w.into(),
            other => {
                eprintln!("unknown argument {other}");
                std::process::exit(2);
            }
        }
        i += 1;
    }
    let all = what == "all";
    let mut report = Report {
        system: format!("{} {}", std::env::consts::OS, std::env::consts::ARCH),
        sizes: (all || what == "sizes").then(bench::sizes),
        unlock: (all || what == "unlock").then(|| bench::unlock(10_000)),
        runs: Vec::new(),
    };
    if all || what == "runs" {
        // Spread over 50 items, and all on one; with the logs pruned three
        // times along the way, and without.
        for (items, compactions) in [(50, 0), (50, 3), (1, 0), (1, 3)] {
            for model in Model::ALL {
                let r = bench::run(model, items, writes, compactions, 7);
                eprintln!(
                    "{:13} items {:2} pruned {} : {:8.0} ms, {}",
                    r.model,
                    items,
                    r.compactions,
                    r.ms,
                    if r.converged && r.violations == 0 {
                        "ok"
                    } else {
                        "FAIL"
                    }
                );
                report.runs.push(r);
            }
        }
    }
    print(&report);
    if let Some(path) = json {
        std::fs::write(&path, serde_json::to_string_pretty(&report).unwrap()).expect("write json");
    }
    let failed = report
        .runs
        .iter()
        .any(|r| r.model == Model::FieldClocks.name() && (!r.converged || r.violations > 0));
    if failed {
        std::process::exit(1);
    }
}

fn print(r: &Report) {
    println!("S4 · sync format on {}\n", r.system);
    if let Some(s) = &r.sizes {
        println!("bytes, one host: body {}, v0 {}", s.body, s.v0);
        println!(
            "  v1 three-way {}, field clocks {}, after 3 edits {}, two parents {}\n",
            s.v1_three_way, s.v1_field_clocks, s.v1_field_clocks_edited, s.v1_two_parents
        );
    }
    if let Some(u) = &r.unlock {
        println!(
            "unlock {} hosts ({} KB v0, {} KB v1), best of 5:",
            u.items,
            u.v0_bytes / 1024,
            u.v1_bytes / 1024
        );
        println!(
            "  v0 {:.1} ms · v1 {:.1} ms · v1 already checked {:.1} ms · v1 + signatures {:.1} ms · v1 + batch {:.1} ms\n",
            u.v0_ms, u.v1_ms, u.v1_stored_ms, u.v1_verify_ms, u.v1_batch_verify_ms
        );
    }
    if !r.runs.is_empty() {
        println!(
            "{:13} {:>5} {:>7} {:>6} {:>9} {:>8} {:>6} {:>5} {:>5}  result",
            "merge", "items", "writes", "pruned", "ms", "µs/write", "revs", "heads", "lost"
        );
        for x in &r.runs {
            let result = match (x.converged, x.violations) {
                (true, 0) => "ok".to_string(),
                (c, v) => format!(
                    "{}{v} lost writes; {}",
                    if c { "" } else { "diverged, " },
                    x.first_violation.as_deref().unwrap_or("")
                ),
            };
            println!(
                "{:13} {:>5} {:>7} {:>6} {:>9.0} {:>8.1} {:>6} {:>5} {:>5}  {}",
                x.model,
                x.items,
                x.writes,
                x.compactions,
                x.ms,
                x.us_per_write,
                x.revisions_per_device,
                x.max_heads,
                x.lost,
                result
            );
        }
    }
}
