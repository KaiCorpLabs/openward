use std::time::{Duration, Instant};

use super::cast::{self, Event, Mark};
use super::*;
use crate::events::Failure;

fn open(dir: &Path) -> Arc<Logs> {
    Logs::open(dir, Config::default()).unwrap()
}

fn begin(record: bool) -> Begin {
    Begin {
        place: Place::Host("0190f0f0-0000-7000-8000-000000000001".into()),
        label: "web-1".into(),
        address: "ops@10.0.4.11".into(),
        marking: Some(Marking {
            name: "Producción".into(),
            short: "prod".into(),
            color: "red".into(),
        }),
        system: Some("deb".into()),
        tmux: false,
        record,
        cols: 80,
        rows: 24,
        term: "xterm-256color".into(),
    }
}

fn outputs(rec: &Recording) -> String {
    rec.events
        .iter()
        .filter_map(|(_, e)| match e {
            Event::Output(s) => Some(s.as_str()),
            _ => None,
        })
        .collect()
}

fn markers(rec: &Recording) -> Vec<String> {
    rec.events
        .iter()
        .filter_map(|(_, e)| match e {
            Event::Marker(label) => Some(label.clone()),
            _ => None,
        })
        .collect()
}

fn until(what: &str, mut ok: impl FnMut() -> bool) {
    let deadline = Instant::now() + Duration::from_secs(5);
    while !ok() {
        assert!(Instant::now() < deadline, "waited too long for {what}");
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn a_session_records_what_came_out_and_reads_back() {
    let tmp = tempfile::tempdir().unwrap();
    let dir = tmp.path().join("logs");
    let logs = open(&dir);
    let session = logs.begin(begin(true)).unwrap();
    let id = session.id();
    assert_eq!(logs.entry(&id).unwrap().end, End::Open);
    session.output("ops@web-1:~$ ".as_bytes());
    session.command("  ls -la ");
    session.output(b"ls -la\r\n");
    // A character cut between two reads.
    session.output(&"total 8 ñ\r\n".as_bytes()[..9]);
    session.output(&"total 8 ñ\r\n".as_bytes()[9..]);
    session.resize(100, 30);
    session.finish(End::Closed);

    let entry = logs.entry(&id).unwrap();
    assert_eq!(entry.end, End::Closed);
    assert!(entry.recorded && entry.bytes > 0);
    assert_eq!(entry.commands, 1);
    assert_eq!(entry.label, "web-1");
    assert!(entry.ended_ms.unwrap() >= entry.started_ms);

    let rec = logs.read(&id).unwrap();
    assert!(rec.complete);
    assert_eq!((rec.header.width, rec.header.height), (80, 24));
    assert_eq!(rec.header.title, "web-1");
    assert_eq!(outputs(&rec), "ops@web-1:~$ ls -la\r\ntotal 8 ñ\r\n");
    assert_eq!(markers(&rec), ["$ ls -la"]);
    assert!(rec.events.iter().any(|(_, e)| *e == Event::Resize(100, 30)));
    let text: Vec<String> = logs
        .text(&id)
        .unwrap()
        .into_iter()
        .map(|(_, l)| l)
        .collect();
    assert_eq!(text, ["ops@web-1:~$ ls -la", "total 8 ñ"]);

    // On disk, readable by its owner only.
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        for ext in ["json", "cast.gz", "txt.gz"] {
            let mode = fs::metadata(dir.join(format!("{id}.{ext}")))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(mode & 0o777, 0o600, "{ext}");
        }
        let mode = fs::metadata(&dir).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o700);
    }

    // And again after a restart.
    drop(logs);
    let again = open(&dir);
    assert_eq!(again.entry(&id), Some(entry));
}

#[test]
fn an_entry_alone_has_no_recording() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let session = logs.begin(begin(false)).unwrap();
    session.output(b"nada\r\n");
    session.command("ls");
    assert!(!session.pause(true));
    let id = session.id();
    drop(session);
    let entry = logs.entry(&id).unwrap();
    assert_eq!(entry.end, End::Closed, "dropping it closes it");
    assert!(!entry.recorded);
    assert_eq!((entry.bytes, entry.commands), (0, 0));
    assert!(logs.read(&id).is_err());
    assert!(!dir.path().join(format!("{id}.cast.gz")).exists());
}

#[test]
fn what_comes_out_while_paused_is_not_kept() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let session = logs.begin(begin(true)).unwrap();
    session.output(b"antes\r\n");
    assert!(session.pause(true));
    assert!(!session.pause(true), "already paused");
    assert!(session.paused());
    // Not even the command run in the pause.
    session.command("cat .env");
    session.output(b"TOKEN=s3cr3t\r\n");
    assert!(session.pause(false));
    session.command("ls");
    session.output(b"despues\r\n");
    session.finish(End::Closed);
    let id = session.id();
    let rec = logs.read(&id).unwrap();
    assert_eq!(outputs(&rec), "antes\r\ndespues\r\n");
    assert_eq!(
        markers(&rec),
        [Mark::Pause.label(), Mark::Resume.label(), "$ ls"]
    );
    assert_eq!(logs.entry(&id).unwrap().commands, 1);
    let text: Vec<String> = logs
        .text(&id)
        .unwrap()
        .into_iter()
        .map(|(_, l)| l)
        .collect();
    assert_eq!(text, ["antes", "despues"]);
}

/// A session open when the app stops (here, another instance opens the
/// directory) keeps what was flushed, and is closed as such.
#[test]
fn a_sudden_exit_keeps_what_was_flushed() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let session = logs.begin(begin(true)).unwrap();
    let id = session.id();
    session.output(b"uno\r\n");
    session.command("ls");
    // A flush comes every two seconds while there is output.
    std::thread::sleep(Duration::from_millis(2600));
    session.output(b"dos\r\n");

    let rec = logs.read(&id).unwrap();
    assert!(!rec.complete);
    assert!(outputs(&rec).starts_with("uno\r\n"));

    let after = open(dir.path());
    let entry = after.entry(&id).unwrap();
    assert_eq!(entry.end, End::AppQuit);
    assert!(entry.ended_ms.is_some() && entry.bytes > 0);
    assert_eq!(outputs(&after.read(&id).unwrap()), outputs(&rec));
    drop(session);
}

fn fake(dir: &Path, id: &str, days_ago: i64, bytes: u64, saved: bool) {
    let started_ms = now_ms() - days_ago * 24 * 60 * 60 * 1000;
    let entry = Entry {
        id: id.into(),
        place: Place::Local,
        label: String::new(),
        address: "~".into(),
        marking: None,
        system: None,
        started_ms,
        ended_ms: Some(started_ms + 60_000),
        end: End::Closed,
        tmux: false,
        recorded: bytes > 0,
        bytes,
        commands: 0,
        saved: saved.then(|| Saved {
            note: "por si acaso".into(),
            at_ms: started_ms,
        }),
    };
    write_entry(dir, &entry).unwrap();
    if bytes > 0 {
        fs::write(dir.join(format!("{id}.cast.gz")), vec![0; bytes as usize]).unwrap();
    }
}

#[test]
fn old_and_oversized_entries_go_saved_ones_stay() {
    let dir = tempfile::tempdir().unwrap();
    fake(dir.path(), "a-old", 40, 100, false);
    fake(dir.path(), "b-old-saved", 40, 100, true);
    fake(dir.path(), "c", 3, 400, false);
    fake(dir.path(), "d", 2, 400, false);
    fake(dir.path(), "e", 1, 400, false);
    let logs = Logs::open(
        dir.path(),
        Config {
            max_bytes: 1000,
            ..Config::default()
        },
    )
    .unwrap();
    // The 40-day-old one went; of the rest, the oldest until it fits
    // (100 saved + 400 + 400 = 900).
    let ids: Vec<String> = logs.list().into_iter().map(|e| e.id).collect();
    assert_eq!(ids, ["e", "d", "b-old-saved"]);
    assert!(!dir.path().join("a-old.json").exists());
    assert!(!dir.path().join("c.cast.gz").exists());
    assert_eq!(
        logs.usage(),
        Usage {
            bytes: 900,
            entries: 3,
            recorded: 3,
            saved: 1
        }
    );

    // Saving keeps it through tighter limits; taking it back lets it go.
    logs.save("d", "  el arreglo  ").unwrap();
    assert_eq!(logs.entry("d").unwrap().saved.unwrap().note, "el arreglo");
    logs.set_config(Config {
        max_bytes: 450,
        ..Config::default()
    });
    let ids: Vec<String> = logs.list().into_iter().map(|e| e.id).collect();
    assert_eq!(ids, ["d", "b-old-saved"]);
    logs.unsave("d").unwrap();
    assert_eq!(logs.list().len(), 1);
    // No limits: nothing goes, at the next start either.
    logs.set_config(Config {
        keep_days: 0,
        max_bytes: 0,
        ..Config::default()
    });
    fake(dir.path(), "f", 400, 10, false);
    let logs = open(dir.path());
    assert_eq!(logs.list().len(), 2);
}

/// The limits chosen are the ones a start prunes with: kept beside the
/// logs, not the defaults the app opens with.
#[test]
fn the_limits_chosen_hold_at_the_next_start() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let chosen = Config {
        record_local: true,
        keep_days: 90,
        max_bytes: 5 * 1024 * 1024 * 1024,
    };
    logs.set_config(chosen);
    drop(logs);
    fake(dir.path(), "sixty-days", 60, 10, false);
    let logs = open(dir.path());
    assert_eq!(logs.config(), chosen);
    assert_eq!(logs.list().len(), 1, "kept 90 days, not 30");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = fs::metadata(dir.path().join(CONFIG_FILE))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }
    // A file not ours to read: the defaults.
    fs::write(dir.path().join(CONFIG_FILE), "{ no").unwrap();
    assert_eq!(open(dir.path()).config(), Config::default());
}

#[test]
fn deleting_leaves_sessions_going_on() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let done = logs.begin(begin(true)).unwrap();
    done.finish(End::Closed);
    let going = logs.begin(begin(true)).unwrap();
    assert!(!logs.delete(&going.id()).unwrap());
    assert!(logs.delete(&done.id()).unwrap());
    assert!(!logs.delete(&done.id()).unwrap());
    assert!(!dir.path().join(format!("{}.cast.gz", done.id())).exists());
    let done = logs.begin(begin(false)).unwrap();
    done.finish(End::Lost);
    assert_eq!(logs.delete_all().unwrap(), 1);
    assert_eq!(logs.list().len(), 1);
    going.finish(End::Closed);
    assert_eq!(logs.delete_all().unwrap(), 1);
    assert!(logs.list().is_empty());
}

#[test]
fn search_finds_lines_ignoring_case_newest_first() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let first = logs.begin(begin(true)).unwrap();
    first.output(b"$ curl -s localhost:8081/health\r\nok\r\n");
    first.finish(End::Closed);
    // Newer by the clock.
    std::thread::sleep(Duration::from_millis(5));
    let second = logs.begin(begin(true)).unwrap();
    second.output(b"LISTEN 0 100 127.0.0.1:8081\r\n");
    for i in 0..30 {
        second.output(format!("line {i} port 8081\r\n").as_bytes());
    }
    second.output(b"\x1b[?1049hvim: 8081\x1b[?1049l");
    second.finish(End::Closed);
    let mut found = Vec::new();
    logs.search("  PORT 8081 ", |f| {
        found.push(f);
        true
    });
    assert_eq!(found.len(), 1);
    assert_eq!(found[0].entry.id, second.id());
    assert_eq!(found[0].total, 30);
    assert_eq!(found[0].hits.len(), HITS_SHOWN);
    assert_eq!(found[0].hits[0].line, "line 0 port 8081");

    let mut ids = Vec::new();
    logs.search("8081", |f| {
        ids.push(f.entry.id.clone());
        true
    });
    assert_eq!(ids, [second.id(), first.id()]);
    // Stopping after the first.
    let mut n = 0;
    logs.search("8081", |_| {
        n += 1;
        false
    });
    assert_eq!(n, 1);
}

#[test]
fn exports_are_asciicast_and_plain_text() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let s = logs.begin(begin(true)).unwrap();
    s.output(b"$ ");
    s.command("sudo nginx -t");
    s.output(b"sudo nginx -t\r\nsyntax is ok\r\ntest is successful\r\n$ ");
    std::thread::sleep(Duration::from_millis(30));
    s.command("sudo systemctl reload nginx");
    s.output(b"sudo systemctl reload nginx\r\n$ ");
    s.finish(End::Closed);
    let id = s.id();

    let cast_file = dir.path().join("out.cast");
    logs.export_cast(&id, &cast_file).unwrap();
    let exported = cast::read(BufReader::new(File::open(&cast_file).unwrap())).unwrap();
    assert_eq!(exported, logs.read(&id).unwrap());

    let text_file = dir.path().join("out.txt");
    logs.export_text(&id, &text_file).unwrap();
    assert_eq!(
        fs::read_to_string(&text_file).unwrap(),
        "$ sudo nginx -t\nsyntax is ok\ntest is successful\n$ sudo systemctl reload nginx\n$\n"
    );

    assert_eq!(
        logs.command_text(&id, 0).unwrap(),
        "$ sudo nginx -t\nsyntax is ok\ntest is successful\n"
    );
    assert_eq!(
        logs.command_text(&id, 1).unwrap(),
        "$ sudo systemctl reload nginx\n"
    );
    assert!(logs.command_text(&id, 2).is_err());
}

fn recording(events: Vec<(f64, Event)>) -> Recording {
    Recording {
        header: Header::new(20, 4, 0, "", ""),
        events,
        complete: true,
    }
}

#[test]
fn the_player_shows_the_screen_of_any_moment() {
    let p = Player::new(
        recording(vec![
            (0.0, Event::Output("uno\r\n".into())),
            (1.0, Event::Output("dos\r\n".into())),
            (1.5, Event::Marker("$ clear".into())),
            (2.0, Event::Output("\x1b[H\x1b[2Jtres".into())),
            (3.0, Event::Resize(30, 5)),
        ]),
        100,
    );
    let screen = || p.terminal().screen_text();
    assert_eq!(p.duration(), 3.0);
    assert_eq!(p.markers(), [(1.5, "$ clear".to_owned())]);
    p.seek(1.2);
    assert!(screen().contains("uno") && screen().contains("dos"));
    p.seek(2.5);
    assert!(screen().contains("tres") && !screen().contains("uno"));
    // Back: from the start again.
    p.seek(0.5);
    assert!(screen().contains("uno") && !screen().contains("dos"));
    assert!(!screen().contains("tres"));
    p.seek(9.0);
    assert_eq!(p.position(), 3.0);
    assert_eq!(p.terminal().size(), openward_term::Size::new(30, 5));
    p.seek(0.0);
    assert_eq!(p.terminal().size(), openward_term::Size::new(20, 4));
}

#[test]
fn playing_moves_on_and_long_silences_go_short() {
    let p = Player::new(
        recording(vec![
            (0.0, Event::Output("uno\r\n".into())),
            (60.0, Event::Output("fin".into())),
        ]),
        100,
    );
    let started = Instant::now();
    p.play(8.0);
    assert!(p.playing());
    until("the end", || !p.playing());
    // A minute of silence plays as two seconds, at 8×: a quarter.
    assert!(started.elapsed() < Duration::from_secs(2));
    assert_eq!(p.position(), 60.0);
    assert!(p.terminal().screen_text().contains("fin"));
    // Again from the start.
    p.play(64.0);
    p.pause();
    assert!(!p.playing());
    assert!(p.position() < 60.0);
}

#[test]
fn a_terminal_feeds_its_log() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let term = crate::Terminal::new(80, 24, 100);
    let session = logs.begin(begin(true)).unwrap();
    term.attach_log(Arc::clone(&session));
    term.feed(b"$ ");
    term.log_command("echo hola");
    term.feed(b"echo hola\r\nhola\r\n");
    term.resize(90, 24);
    assert!(term.pause_log(true));
    let state = term.log_state().unwrap();
    assert!(state.recording && state.paused && state.failed.is_none());
    assert_eq!(state.id, session.id());
    term.feed(b"oculto\r\n");
    assert!(term.pause_log(false));
    term.close();
    assert!(term.log_state().is_none());
    let rec = logs.read(&session.id()).unwrap();
    assert_eq!(outputs(&rec), "$ echo hola\r\nhola\r\n");
    assert!(rec.events.iter().any(|(_, e)| *e == Event::Resize(90, 24)));
    assert_eq!(logs.entry(&session.id()).unwrap().end, End::Closed);
}

struct Collect(Mutex<Vec<crate::Event>>);

impl crate::EventSink for Collect {
    fn send(&self, event: crate::Event) {
        lock(&self.0).push(event);
    }
}

#[test]
fn a_connection_s_events_begin_mark_and_end_its_log() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let term = crate::Terminal::new(80, 24, 100);
    let ui = Arc::new(Collect(Mutex::new(Vec::new())));
    let sink = LogSink::new(ui.clone(), &logs, &term, begin(true));
    let send = |e: crate::Event| crate::EventSink::send(&*sink, e);
    // Nothing before the shell is up.
    send(crate::Event::Persistent {
        session: "ow-1".into(),
        state: crate::events::Persistence::Resumed,
    });
    assert!(logs.list().is_empty() && term.log_state().is_none());
    send(crate::Event::Started {
        program: "sh".into(),
    });
    let id = term.log_state().unwrap().id;
    term.feed(b"uno\r\n");
    send(crate::Event::Reconnecting {
        attempt: 1,
        delay_ms: 1000,
        reason: Failure::lost("web-1".into()),
    });
    send(crate::Event::Reconnecting {
        attempt: 2,
        delay_ms: 2000,
        reason: Failure::lost("web-1".into()),
    });
    send(crate::Event::Started {
        program: "sh".into(),
    });
    assert_eq!(term.log_state().unwrap().id, id, "the same log goes on");
    term.feed(b"dos\r\n");
    send(crate::Event::Closed {
        exit_code: None,
        failure: Some(Failure::lost("web-1".into())),
    });
    assert!(term.log_state().is_none());
    let entry = logs.entry(&id).unwrap();
    assert_eq!(entry.end, End::Lost);
    assert!(entry.tmux);
    let rec = logs.read(&id).unwrap();
    assert_eq!(outputs(&rec), "uno\r\ndos\r\n");
    assert_eq!(markers(&rec), [Mark::Lost.label(), Mark::Back.label()]);
    // The UI heard everything.
    assert_eq!(lock(&ui.0).len(), 6);

    // A connection that never comes up leaves no entry.
    let sink = LogSink::new(ui, &logs, &term, begin(true));
    crate::EventSink::send(
        &*sink,
        crate::Event::Closed {
            exit_code: None,
            failure: Some(Failure::Other("no".into())),
        },
    );
    assert_eq!(logs.list().len(), 1);
}

/// What recording costs a terminal flooded with output (a `cat` of a big
/// log). A measurement, not a check:
/// `cargo test --release -p openward-app --lib recording_costs -- --ignored --nocapture`.
#[test]
#[ignore = "a measurement: run it in release"]
fn recording_costs_little() {
    let mut chunk = Vec::new();
    let mut i = 0;
    while chunk.len() < 64 * 1024 {
        chunk.extend_from_slice(
            format!(
                "\x1b[32m2026-10-28 11:18:{:02}\x1b[0m web-1 app[2231]: GET /api/orders/{i} 200 {}ms\r\n",
                i % 60,
                i % 97
            )
            .as_bytes(),
        );
        i += 1;
    }
    let total: usize = 256 * 1024 * 1024;
    let feed = |term: &crate::Terminal| {
        let started = Instant::now();
        let mut fed = 0;
        while fed < total {
            term.feed(&chunk);
            fed += chunk.len();
        }
        started.elapsed()
    };
    let mb = total as f64 / (1024.0 * 1024.0);
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());

    // Rounds in turn, the best of each: a busy machine or a warm-up
    // should not count against either.
    let (mut without, mut with) = (Duration::MAX, Duration::MAX);
    let (mut id, mut drained) = (String::new(), Duration::ZERO);
    for _ in 0..3 {
        let plain = crate::Terminal::new(120, 40, 10_000);
        without = without.min(feed(&plain));

        let session = logs.begin(begin(true)).unwrap();
        id = session.id();
        let term = crate::Terminal::new(120, 40, 10_000);
        term.attach_log(session);
        with = with.min(feed(&term));
        let drain = Instant::now();
        term.close();
        drained = drain.elapsed();
    }
    let entry = logs.entry(&id).unwrap();
    let rec = logs.read(&id).unwrap();
    let kept: usize = rec
        .events
        .iter()
        .map(|(_, e)| match e {
            Event::Output(s) => s.len(),
            _ => 0,
        })
        .sum();
    let omitted = markers(&rec).iter().any(|m| m == Mark::Omitted.label());
    println!(
        "{mb:.0} MB: {:.0} MB/s without recording, {:.0} MB/s with it ({:+.1} %); \
         the writer finished {:.2} s after; kept {:.0} MB of output{}; on disk {:.1} MB",
        mb / without.as_secs_f64(),
        mb / with.as_secs_f64(),
        (with.as_secs_f64() / without.as_secs_f64() - 1.0) * 100.0,
        drained.as_secs_f64(),
        kept as f64 / (1024.0 * 1024.0),
        if omitted { " (some left out)" } else { "" },
        entry.bytes as f64 / (1024.0 * 1024.0),
    );
}

/// Where the writer's time goes, stage by stage, on 64 MB of log lines.
/// `cargo test --release -p openward-app --lib writer_stages -- --ignored --nocapture`.
#[test]
#[ignore = "a measurement: run it in release"]
fn writer_stages() {
    use flate2::Compression;
    use flate2::write::GzEncoder;
    let mut chunk = Vec::new();
    let mut i = 0;
    while chunk.len() < 64 * 1024 {
        chunk.extend_from_slice(
            format!(
                "\x1b[32m2026-10-28 11:18:{:02}\x1b[0m web-1 app[2231]: GET /api/orders/{i} 200 {}ms\r\n",
                i % 60,
                i % 97
            )
            .as_bytes(),
        );
        i += 1;
    }
    let n = 1024;
    let mb = (chunk.len() * n) as f64 / (1024.0 * 1024.0);
    let rate = |what: &str, started: Instant| {
        println!("{what}: {:.0} MB/s", mb / started.elapsed().as_secs_f64());
    };
    let mut utf8 = cast::Utf8Stream::default();
    let t = Instant::now();
    let texts: Vec<String> = (0..n).map(|_| utf8.decode(&chunk)).collect();
    rate("decode", t);
    let mut filter = super::text::TextFilter::default();
    let mut lines = String::new();
    let t = Instant::now();
    for s in &texts {
        filter.feed(0.0, s, &mut |t, l| {
            use std::fmt::Write as _;
            let _ = writeln!(lines, "{t:.3}\t{l}");
        });
        if lines.len() > 1 << 20 {
            lines.clear();
        }
    }
    rate("text filter", t);
    let mut out = String::new();
    let t = Instant::now();
    let mut events = Vec::new();
    for s in &texts {
        cast::push_event(&mut out, 1.0, 'o', s);
        events.push(std::mem::take(&mut out));
    }
    rate("json", t);
    for (name, level) in [
        ("gzip default", Compression::default()),
        ("gzip fast", Compression::fast()),
    ] {
        let mut gz = GzEncoder::new(std::io::sink(), level);
        let t = Instant::now();
        for e in &events {
            gz.write_all(e.as_bytes()).unwrap();
        }
        gz.finish().unwrap();
        rate(name, t);
    }
}

#[test]
fn a_preview_has_the_last_lines_and_the_markers() {
    let dir = tempfile::tempdir().unwrap();
    let logs = open(dir.path());
    let s = logs.begin(begin(true)).unwrap();
    for i in 0..10 {
        s.output(format!("línea {i}\r\n").as_bytes());
    }
    s.command("df -h");
    s.output(b"/dev/sdb1 95% \"lleno\"\r\n");
    assert!(s.pause(true));
    s.finish(End::Lost);
    let id = s.id();

    let p = logs.preview(&id, 3).unwrap();
    let lines: Vec<&str> = p.lines.iter().map(|(_, l)| l.as_str()).collect();
    assert_eq!(lines, ["línea 8", "línea 9", "/dev/sdb1 95% \"lleno\""]);
    let labels: Vec<&str> = p.markers.iter().map(|(_, l)| l.as_str()).collect();
    assert_eq!(labels, ["$ df -h", "pause"]);
    assert_eq!(logs.markers(&id).unwrap(), p.markers);

    assert!(
        logs.plain_text(&id)
            .unwrap()
            .starts_with("línea 0\nlínea 1\n")
    );

    // Around a moment: the lines before it and from it on.
    let s = logs.begin(begin(true)).unwrap();
    s.output(b"uno\r\ndos\r\n");
    std::thread::sleep(Duration::from_millis(50));
    s.output(b"tres\r\ncuatro\r\ncinco\r\n");
    s.finish(End::Closed);
    let text = logs.text(&s.id()).unwrap();
    let around: Vec<String> = logs
        .lines_around(&s.id(), text[2].0, 1, 2)
        .unwrap()
        .into_iter()
        .map(|(_, l)| l)
        .collect();
    assert_eq!(around, ["dos", "tres", "cuatro"]);

    // An entry alone has nothing to show.
    let alone = logs.begin(begin(false)).unwrap();
    alone.finish(End::Closed);
    assert!(logs.preview(&alone.id(), 3).is_err());
}
