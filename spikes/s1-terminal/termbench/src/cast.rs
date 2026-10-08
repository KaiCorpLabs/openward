//! Minimal asciicast reader (v2 and v3): extracts the output stream and the
//! recorded terminal size. Timing is ignored; the benchmark measures how fast
//! an engine can consume the bytes.

use std::fs;
use std::path::Path;

use serde_json::Value;

pub struct Cast {
    pub cols: u16,
    pub rows: u16,
    pub output: Vec<u8>,
}

pub fn read(path: &Path) -> Result<Cast, String> {
    let text = fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut lines = text.lines().filter(|l| !l.trim().is_empty());
    let header: Value = lines
        .next()
        .ok_or("empty cast file")
        .and_then(|l| serde_json::from_str(l).map_err(|_| "header is not JSON"))?;
    let (cols, rows) = match header["version"].as_u64() {
        Some(2) => (header["width"].as_u64(), header["height"].as_u64()),
        Some(3) => (
            header["term"]["cols"].as_u64(),
            header["term"]["rows"].as_u64(),
        ),
        other => return Err(format!("unsupported asciicast version {other:?}")),
    };
    let (Some(cols), Some(rows)) = (cols, rows) else {
        return Err("header lacks terminal size".into());
    };
    let mut output = Vec::new();
    for (n, line) in lines.enumerate() {
        let event: Value =
            serde_json::from_str(line).map_err(|_| format!("event {n} is not JSON"))?;
        if event[1].as_str() == Some("o")
            && let Some(data) = event[2].as_str()
        {
            output.extend_from_slice(data.as_bytes());
        }
    }
    Ok(Cast {
        cols: cols as u16,
        rows: rows as u16,
        output,
    })
}
