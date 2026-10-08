//! The four measurements of spike S1 on the core side.

use std::fmt::Write as _;
use std::fs;
use std::path::Path;
use std::time::{Duration, Instant};

use openward_term::{FrameEncoder, Size, TermEngine};
use serde_json::json;

use crate::{Opts, cast, make_engine, rss};

struct Throughput {
    bytes: usize,
    parse_only: Duration,
    with_frames: Duration,
    frames: usize,
    frame_bytes_avg: f64,
    frame_bytes_max: u32,
    encode: Percentiles,
}

struct Percentiles {
    p50: Duration,
    p95: Duration,
    p99: Duration,
    max: Duration,
}

impl Percentiles {
    fn of(mut samples: Vec<Duration>) -> Self {
        samples.sort_unstable();
        let at = |q: f64| {
            if samples.is_empty() {
                Duration::ZERO
            } else {
                samples[((samples.len() - 1) as f64 * q).round() as usize]
            }
        };
        Self {
            p50: at(0.50),
            p95: at(0.95),
            p99: at(0.99),
            max: samples.last().copied().unwrap_or_default(),
        }
    }
}

fn mib_per_s(bytes: usize, d: Duration) -> f64 {
    bytes as f64 / 1_048_576.0 / d.as_secs_f64().max(f64::EPSILON)
}

fn us(d: Duration) -> f64 {
    d.as_secs_f64() * 1e6
}

/// Feed `data` twice: once parsing only, once encoding a frame every
/// `frame_bytes` of input, which stands in for the UI's frame tick.
fn throughput(engine: &str, size: Size, data: &[u8], o: &Opts) -> Result<Throughput, String> {
    let mut e = make_engine(engine, size, o.scrollback)?;
    let start = Instant::now();
    for chunk in data.chunks(o.chunk) {
        e.feed(chunk);
        e.take_host_writes();
    }
    let parse_only = start.elapsed();

    let mut e = make_engine(engine, size, o.scrollback)?;
    let mut enc = FrameEncoder::new();
    let mut encode_times = Vec::new();
    let (mut sum, mut max, mut pending) = (0u64, 0u32, 0usize);
    let start = Instant::now();
    for chunk in data.chunks(o.chunk) {
        e.feed(chunk);
        e.take_host_writes();
        pending += chunk.len();
        if pending >= o.frame_bytes {
            pending = 0;
            let t = Instant::now();
            let stats = e.encode_damage(&mut enc);
            encode_times.push(t.elapsed());
            sum += u64::from(stats.bytes);
            max = max.max(stats.bytes);
        }
    }
    let t = Instant::now();
    let stats = e.encode_damage(&mut enc);
    encode_times.push(t.elapsed());
    sum += u64::from(stats.bytes);
    max = max.max(stats.bytes);
    let with_frames = start.elapsed();

    Ok(Throughput {
        bytes: data.len(),
        parse_only,
        with_frames,
        frames: encode_times.len(),
        frame_bytes_avg: sum as f64 / encode_times.len() as f64,
        frame_bytes_max: max,
        encode: Percentiles::of(encode_times),
    })
}

fn report(engine: &str, input: &str, size: Size, t: &Throughput, o: &Opts) {
    if o.json {
        println!(
            "{}",
            json!({
                "kind": "throughput", "engine": engine, "input": input,
                "cols": size.cols, "rows": size.rows, "bytes": t.bytes,
                "parse_mib_s": mib_per_s(t.bytes, t.parse_only),
                "with_frames_mib_s": mib_per_s(t.bytes, t.with_frames),
                "frames": t.frames, "frame_bytes_avg": t.frame_bytes_avg, "frame_bytes_max": t.frame_bytes_max,
                "encode_us_p50": us(t.encode.p50), "encode_us_p95": us(t.encode.p95),
                "encode_us_p99": us(t.encode.p99), "encode_us_max": us(t.encode.max),
            })
        );
    } else {
        println!(
            "{engine:<18} {input:<28} {:>8.1} MiB/s parse  {:>8.1} MiB/s +frames  {:>6} frames  avg {:>7.0} B  max {:>7} B  encode p95 {:>7.1} µs  max {:>7.1} µs",
            mib_per_s(t.bytes, t.parse_only),
            mib_per_s(t.bytes, t.with_frames),
            t.frames,
            t.frame_bytes_avg,
            t.frame_bytes_max,
            us(t.encode.p95),
            us(t.encode.max),
        );
    }
}

pub fn run_files(o: &Opts) -> Result<(), String> {
    if o.positional.is_empty() {
        return Err("run needs at least one input file (see `termbench gen`)".into());
    }
    let size = Size::new(o.cols, o.rows);
    for path in &o.positional {
        let data = fs::read(path).map_err(|e| format!("{path}: {e}"))?;
        let name = file_name(path);
        for engine in &o.engines {
            report(engine, &name, size, &throughput(engine, size, &data, o)?, o);
        }
    }
    report_peak(o);
    Ok(())
}

pub fn replay_casts(o: &Opts) -> Result<(), String> {
    if o.positional.is_empty() {
        return Err("replay needs at least one .cast file".into());
    }
    for path in &o.positional {
        let cast = cast::read(Path::new(path))?;
        let size = Size::new(cast.cols, cast.rows);
        let name = file_name(path);
        for engine in &o.engines {
            report(
                engine,
                &name,
                size,
                &throughput(engine, size, &cast.output, o)?,
                o,
            );
        }
    }
    report_peak(o);
    Ok(())
}

/// Keystroke echo: one byte in, one frame out, as when a user types and the
/// host echoes. This is the core's share of the input-to-paint latency.
pub fn echo(o: &Opts) -> Result<(), String> {
    let size = Size::new(o.cols, o.rows);
    for engine in &o.engines {
        let mut e = make_engine(engine, size, o.scrollback)?;
        let mut enc = FrameEncoder::new();
        // Start from a busy screen so damage tracking has real work.
        let mut screen = String::new();
        for i in 0..usize::from(o.rows) {
            let _ = write!(screen, "\x1b[3{}mprompt line {i}\x1b[0m\r\n", i % 8);
        }
        e.feed(screen.as_bytes());
        e.encode_damage(&mut enc);

        let mut samples = Vec::with_capacity(o.iterations);
        let mut col = 0usize;
        for i in 0..o.iterations {
            let byte = if col + 1 >= usize::from(o.cols) {
                col = 0;
                b'\n'
            } else {
                col += 1;
                b'a' + (i % 26) as u8
            };
            let t = Instant::now();
            e.feed(if byte == b'\n' {
                b"\r\n"
            } else {
                std::slice::from_ref(&byte)
            });
            e.encode_damage(&mut enc);
            samples.push(t.elapsed());
        }
        let p = Percentiles::of(samples);
        if o.json {
            println!(
                "{}",
                json!({
                    "kind": "echo", "engine": engine, "cols": o.cols, "rows": o.rows,
                    "iterations": o.iterations, "us_p50": us(p.p50), "us_p95": us(p.p95),
                    "us_p99": us(p.p99), "us_max": us(p.max),
                })
            );
        } else {
            println!(
                "{engine:<18} echo {}x{}  p50 {:>6.1} µs  p95 {:>6.1} µs  p99 {:>6.1} µs  max {:>7.1} µs",
                o.cols,
                o.rows,
                us(p.p50),
                us(p.p95),
                us(p.p99),
                us(p.max)
            );
        }
    }
    Ok(())
}

/// Memory with N tabs and full scrollback. Run one engine per process: the
/// peak RSS is process-wide.
pub fn mem(o: &Opts) -> Result<(), String> {
    let [engine] = o.engines.as_slice() else {
        return Err("mem measures one engine per process; pass --engine alacritty (or another single engine)".into());
    };
    let size = Size::new(o.cols, o.rows);
    let before = rss::peak_bytes();
    let mut tabs: Vec<Box<dyn TermEngine>> = Vec::with_capacity(o.tabs);
    let mut line = String::new();
    for tab in 0..o.tabs {
        let mut e = make_engine(engine, size, o.scrollback)?;
        for n in 0..o.scrollback + usize::from(o.rows) {
            line.clear();
            let _ = write!(line, "\x1b[3{}m{tab:02}:{n:06}\x1b[0m ", n % 8);
            while line.len() < usize::from(o.cols) {
                line.push_str("lorem ipsum dolor ");
            }
            line.push_str("\r\n");
            e.feed(line.as_bytes());
        }
        tabs.push(e);
    }
    let after = rss::peak_bytes();
    let fmt = |b: Option<u64>| {
        b.map_or("n/a".to_owned(), |b| {
            format!("{:.1} MiB", b as f64 / 1_048_576.0)
        })
    };
    if o.json {
        println!(
            "{}",
            json!({
                "kind": "mem", "engine": engine, "tabs": o.tabs, "scrollback": o.scrollback,
                "cols": o.cols, "rows": o.rows, "peak_rss_before": before, "peak_rss_after": after,
            })
        );
    } else {
        println!(
            "{engine:<18} {} tabs × {} lines × {} cols  peak RSS {} → {}",
            o.tabs,
            o.scrollback,
            o.cols,
            fmt(before),
            fmt(after)
        );
    }
    drop(tabs);
    Ok(())
}

fn report_peak(o: &Opts) {
    if !o.json
        && let Some(b) = rss::peak_bytes()
    {
        println!(
            "peak RSS of this process: {:.1} MiB",
            b as f64 / 1_048_576.0
        );
    }
}

fn file_name(path: &str) -> String {
    Path::new(path)
        .file_name()
        .map_or_else(|| path.to_owned(), |n| n.to_string_lossy().into_owned())
}
