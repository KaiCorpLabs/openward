//! Convergence with proptest: random writes, pushes, partial reads, clock
//! skews and pruned logs on three devices; then everyone reads everything,
//! and the oracle checks every write. And the cases worth naming.

use ciborium::Value;
use proptest::prelude::*;
use proptest::strategy::Union;
use syncsim::dag::Model;
use syncsim::sim::{Op, Outcome, PATHS, Sim};

const DEVICES: usize = 3;
const ITEMS: usize = 2;
/// How far ahead another device's clock may be and still be followed.
const AHEAD_MS: u64 = 60_000;

fn op(prune: bool) -> BoxedStrategy<Op> {
    let write = (
        0..DEVICES,
        0..ITEMS,
        0..PATHS.len(),
        proptest::option::weighted(0.85, 0u8..4),
    )
        .prop_map(|(device, item, path, value)| Op::Write {
            device,
            item,
            path,
            value,
        });
    let push = (0..DEVICES).prop_map(|device| Op::Push { device });
    let pull = (0..DEVICES, 0..DEVICES, 1usize..4).prop_map(|(reader, writer, max)| Op::Pull {
        reader,
        writer,
        max,
    });
    let wait = (0u32..5000).prop_map(|ms| Op::Wait { ms });
    let mut arms = vec![
        (5, write.boxed()),
        (2, push.boxed()),
        (3, pull.boxed()),
        (1, wait.boxed()),
    ];
    if prune {
        arms.push((
            1,
            (0..DEVICES)
                .prop_map(|device| Op::Compact { device })
                .boxed(),
        ));
    }
    Union::new_weighted(arms).boxed()
}

/// Wall clocks up to two minutes off either way: some devices do not
/// follow the others' clocks.
fn skews() -> impl Strategy<Value = Vec<i64>> {
    proptest::collection::vec(-120_000i64..120_000, DEVICES)
}

fn run(model: Model, skews: &[i64], ops: &[Op]) -> Outcome {
    let mut sim = Sim::new(model, skews, ITEMS, AHEAD_MS);
    for op in ops {
        sim.apply(op);
    }
    sim.settle();
    sim.check()
}

proptest! {
    #![proptest_config(ProptestConfig { cases: 2000, ..ProptestConfig::default() })]

    #[test]
    fn field_clocks_converge_and_keep_the_last_writes(
        skews in skews(),
        ops in proptest::collection::vec(op(true), 0..150),
    ) {
        let out = run(Model::FieldClocks, &skews, &ops);
        prop_assert!(out.converged, "diverged");
        prop_assert!(out.violations.is_empty(), "{:#?}", out.violations);
    }
}

// The same property fails for three-way at once, with the whole history:
// proptest shrank it to the case below.

/// Device 2 unsets the label. Device 1 unsets it too, without seeing that,
/// and puts it back; device 0 sees device 2's unset and puts it back. Both
/// unsets were undone by someone who saw them, so the label must stay.
fn both_unsets_undone(model: Model) -> Outcome {
    let unset = |device| Op::Write {
        device,
        item: 0,
        path: 0,
        value: None,
    };
    let mut sim = Sim::new(model, &[0, 0, 0], 1, AHEAD_MS);
    for op in [
        unset(2),
        Op::Push { device: 2 },
        unset(1),
        write(1, 0, 0),
        Op::Pull {
            reader: 0,
            writer: 2,
            max: 10,
        },
        write(0, 0, 0),
        // Each merges with one unset it has not seen undone, and writes
        // another field.
        Op::Pull {
            reader: 1,
            writer: 2,
            max: 10,
        },
        write(1, 1, 7),
        Op::Push { device: 1 },
        Op::Pull {
            reader: 0,
            writer: 1,
            max: 1,
        },
        write(0, 1, 8),
    ] {
        sim.apply(&op);
    }
    sim.settle();
    sim.check()
}

#[test]
fn three_way_brings_back_an_unset_that_both_devices_had_undone() {
    let out = both_unsets_undone(Model::ThreeWay);
    assert!(
        out.violations
            .iter()
            .any(|v| v.contains("label: has unset, the last writes were 0 or 0")),
        "{:#?}",
        out.violations
    );
    assert!(both_unsets_undone(Model::FieldClocks).ok());
}

fn write(device: usize, path: usize, value: u8) -> Op {
    Op::Write {
        device,
        item: 0,
        path,
        value: Some(value),
    }
}

fn label(sim: &Sim, device: usize) -> Option<Value> {
    sim.state(device)
        .values()
        .next()
        .and_then(|f| f.get(PATHS[0]).cloned())
}

/// Device 2 stays away while the others edit the label and the logs are
/// pruned; then it edits the port and comes back.
fn away_while_pruned(model: Model) -> Outcome {
    let mut sim = Sim::new(model, &[0, 0, 0], 1, AHEAD_MS);
    for op in [
        write(0, 0, 1),
        Op::Push { device: 0 },
        Op::Wait { ms: 1000 },
        Op::Pull {
            reader: 1,
            writer: 0,
            max: 10,
        },
        write(1, 0, 2),
        Op::Push { device: 1 },
        Op::Wait { ms: 1000 },
        Op::Compact { device: 0 },
        Op::Wait { ms: 1000 },
        write(2, 1, 3),
    ] {
        sim.apply(&op);
    }
    sim.settle();
    sim.check()
}

#[test]
fn back_after_the_logs_were_pruned_field_clocks_keep_every_write() {
    let out = away_while_pruned(Model::FieldClocks);
    assert!(out.ok(), "{:#?}", out.violations);
}

#[test]
fn back_after_the_logs_were_pruned_three_way_reverts_the_label() {
    let out = away_while_pruned(Model::ThreeWay);
    assert!(!out.converged);
    assert!(
        out.violations
            .iter()
            .any(|v| v.starts_with("device 2") && v.contains("label: has 0")),
        "{:#?}",
        out.violations
    );
}

#[test]
fn a_device_behind_still_overwrites_what_it_saw() {
    for model in Model::ALL {
        // Device 1's clock is ten minutes behind.
        let mut sim = Sim::new(model, &[0, -600_000, 0], 1, AHEAD_MS);
        for op in [
            write(0, 0, 1),
            Op::Push { device: 0 },
            Op::Pull {
                reader: 1,
                writer: 0,
                max: 10,
            },
            write(1, 0, 2),
        ] {
            sim.apply(&op);
        }
        sim.settle();
        assert!(sim.check().ok(), "{}", model.name());
        assert_eq!(label(&sim, 2), Some(Value::from(2)), "{}", model.name());
    }
}

#[test]
fn a_clock_a_day_ahead_is_not_followed_and_its_write_still_loses_to_a_later_one() {
    let mut sim = Sim::new(Model::FieldClocks, &[0, 0, 86_400_000], 1, AHEAD_MS);
    for op in [
        write(2, 0, 1),
        Op::Push { device: 2 },
        Op::Pull {
            reader: 0,
            writer: 2,
            max: 10,
        },
        write(0, 0, 2),
    ] {
        sim.apply(&op);
    }
    sim.settle();
    assert!(sim.stats.clocks_not_followed > 0);
    assert!(sim.check().ok());
    assert_eq!(label(&sim, 1), Some(Value::from(2)));
}

#[test]
fn concurrent_writes_to_one_field_leave_one_notice() {
    let mut sim = Sim::new(Model::FieldClocks, &[0, 0, 0], 1, AHEAD_MS);
    // Both edit the label without seeing each other; one edits the port too.
    for op in [write(0, 0, 1), write(1, 0, 2), write(1, 1, 3)] {
        sim.apply(&op);
    }
    sim.settle();
    let out = sim.check();
    assert!(out.ok());
    assert_eq!(out.lost, 1);

    // One after seeing the other: no notice.
    let mut sim = Sim::new(Model::FieldClocks, &[0, 0, 0], 1, AHEAD_MS);
    for op in [
        write(0, 0, 1),
        Op::Push { device: 0 },
        Op::Pull {
            reader: 1,
            writer: 0,
            max: 10,
        },
        write(1, 0, 2),
    ] {
        sim.apply(&op);
    }
    sim.settle();
    let out = sim.check();
    assert!(out.ok());
    assert_eq!(out.lost, 0);
}
