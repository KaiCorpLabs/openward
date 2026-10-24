//! A read-only LevelDB reader, enough for Chromium's IndexedDB.
//!
//! It never opens the database the LevelDB way, which would take its lock
//! and could write: it reads the files. `CURRENT` names the manifest, the
//! manifest says which table files are live and from which log on, and
//! every entry of those tables and logs is read. The newest version of each
//! key wins (the highest sequence number); a deletion hides it.
//!
//! Ordering does not matter here, so Chromium's own key comparator
//! (`idb_cmp1`) is not needed.

use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// A key and its value.
pub type Entry = (Vec<u8>, Vec<u8>);

/// A put (with its value) or a deletion, with its sequence number.
type Change = (Vec<u8>, u64, Option<Vec<u8>>);

/// The live entries of a database, in no particular order.
pub fn read(dir: &Path) -> io::Result<Vec<Entry>> {
    let files = live_files(dir)?;
    let mut newest: HashMap<Vec<u8>, (u64, Option<Vec<u8>>)> = HashMap::new();
    let mut keep = |key: Vec<u8>, seq: u64, value: Option<Vec<u8>>| match newest.get(&key) {
        Some((s, _)) if *s >= seq => {}
        _ => {
            newest.insert(key, (seq, value));
        }
    };
    for table in &files.tables {
        let bytes = crate::files::read(table)?;
        for (internal, value) in table_entries(&bytes).map_err(|e| bad(table, e))? {
            let (key, seq, kind) = split_internal(&internal).map_err(|e| bad(table, e))?;
            keep(key.to_vec(), seq, (kind == VALUE).then_some(value));
        }
    }
    for log in &files.logs {
        let bytes = crate::files::read(log)?;
        for record in log_records(&bytes).map_err(|e| bad(log, e))? {
            for (key, seq, value) in batch_entries(&record).map_err(|e| bad(log, e))? {
                keep(key, seq, value);
            }
        }
    }
    Ok(newest
        .into_iter()
        .filter_map(|(k, (_, v))| v.map(|v| (k, v)))
        .collect())
}

/// How many table and log files [`read`] reads.
pub fn file_counts(dir: &Path) -> io::Result<(usize, usize)> {
    let files = live_files(dir)?;
    Ok((files.tables.len(), files.logs.len()))
}

const VALUE: u8 = 1;
const DELETION: u8 = 0;

fn bad(path: &Path, what: String) -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidData,
        format!("{}: {what}", path.display()),
    )
}

struct Files {
    tables: Vec<PathBuf>,
    logs: Vec<PathBuf>,
}

/// The table files the manifest lists as live, and the logs from its log
/// number on. Without a manifest (a copy without `CURRENT`, say), every
/// table and log in the folder.
fn live_files(dir: &Path) -> io::Result<Files> {
    let mut tables = Vec::new();
    let mut logs = Vec::new();
    for entry in fs::read_dir(dir)? {
        let path = entry?.path();
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let Some((number, ext)) = name.split_once('.') else {
            continue;
        };
        let Ok(number) = number.parse::<u64>() else {
            continue;
        };
        match ext {
            "ldb" | "sst" => tables.push((number, path)),
            "log" => logs.push((number, path)),
            _ => {}
        }
    }
    tables.sort();
    logs.sort();
    let current = dir.join("CURRENT");
    if let Ok(name) = crate::files::read_to_string(&current) {
        let manifest = dir.join(name.trim());
        let bytes = crate::files::read(&manifest)?;
        let version = manifest_version(&bytes).map_err(|e| bad(&manifest, e))?;
        tables.retain(|(n, _)| version.files.contains(n));
        let from = match version.prev_log {
            Some(prev) if prev != 0 => prev.min(version.log),
            _ => version.log,
        };
        logs.retain(|(n, _)| *n >= from);
    }
    Ok(Files {
        tables: tables.into_iter().map(|(_, p)| p).collect(),
        logs: logs.into_iter().map(|(_, p)| p).collect(),
    })
}

// ------------------------------------------------------------------ varints

pub(crate) struct Reader<'a> {
    pub(crate) data: &'a [u8],
    pub(crate) pos: usize,
}

impl<'a> Reader<'a> {
    pub(crate) fn new(data: &'a [u8]) -> Self {
        Self { data, pos: 0 }
    }

    pub(crate) fn done(&self) -> bool {
        self.pos >= self.data.len()
    }

    pub(crate) fn rest(&self) -> &'a [u8] {
        &self.data[self.pos.min(self.data.len())..]
    }

    pub(crate) fn byte(&mut self) -> Result<u8, String> {
        let b = *self.data.get(self.pos).ok_or("truncated")?;
        self.pos += 1;
        Ok(b)
    }

    pub(crate) fn bytes(&mut self, n: usize) -> Result<&'a [u8], String> {
        let end = self.pos.checked_add(n).ok_or("length overflow")?;
        let out = self.data.get(self.pos..end).ok_or("truncated")?;
        self.pos = end;
        Ok(out)
    }

    pub(crate) fn varint(&mut self) -> Result<u64, String> {
        let mut out = 0u64;
        for shift in (0..64).step_by(7) {
            let b = self.byte()?;
            out |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Ok(out);
            }
        }
        Err("varint too long".into())
    }

    pub(crate) fn len(&mut self) -> Result<usize, String> {
        usize::try_from(self.varint()?).map_err(|_| "length overflow".into())
    }

    fn slice(&mut self) -> Result<&'a [u8], String> {
        let n = self.len()?;
        self.bytes(n)
    }

    fn u32_le(&mut self) -> Result<u32, String> {
        Ok(u32::from_le_bytes(self.bytes(4)?.try_into().unwrap()))
    }

    fn u64_le(&mut self) -> Result<u64, String> {
        Ok(u64::from_le_bytes(self.bytes(8)?.try_into().unwrap()))
    }
}

/// `user key | (sequence << 8 | kind)`, the last 8 bytes little-endian.
fn split_internal(key: &[u8]) -> Result<(&[u8], u64, u8), String> {
    if key.len() < 8 {
        return Err("internal key too short".into());
    }
    let (user, tag) = key.split_at(key.len() - 8);
    let tag = u64::from_le_bytes(tag.try_into().unwrap());
    Ok((user, tag >> 8, (tag & 0xff) as u8))
}

// ------------------------------------------------------------------- tables

const TABLE_MAGIC: u64 = 0xdb47_7524_8b80_fb57;
const FOOTER: usize = 48;

/// Every entry of a table file: internal key and value.
fn table_entries(file: &[u8]) -> Result<Vec<Entry>, String> {
    if file.len() < FOOTER {
        return Err("table too short".into());
    }
    let footer = &file[file.len() - FOOTER..];
    let magic = u64::from_le_bytes(footer[40..].try_into().unwrap());
    if magic != TABLE_MAGIC {
        return Err("not a table file".into());
    }
    let mut r = Reader::new(&footer[..40]);
    let _metaindex = (r.varint()?, r.varint()?);
    let index = (r.varint()?, r.varint()?);
    let mut out = Vec::new();
    for (_, handle) in block_entries(&block(file, index)?)? {
        let mut h = Reader::new(&handle);
        let data = block(file, (h.varint()?, h.varint()?))?;
        out.extend(block_entries(&data)?);
    }
    Ok(out)
}

/// A block's contents, uncompressed. After it come a compression byte and
/// a checksum, which is not checked: a damaged block fails to parse.
fn block(file: &[u8], (offset, size): (u64, u64)) -> Result<Vec<u8>, String> {
    let start = usize::try_from(offset).map_err(|_| "offset overflow")?;
    let size = usize::try_from(size).map_err(|_| "size overflow")?;
    let end = start.checked_add(size).ok_or("size overflow")?;
    let data = file.get(start..end).ok_or("block out of the file")?;
    match file.get(end) {
        Some(0) => Ok(data.to_vec()),
        Some(1) => {
            // The length it says it unpacks to, from the file: bounded
            // before anything is reserved.
            let len = snap::raw::decompress_len(data).map_err(|e| format!("snappy: {e}"))?;
            if len as u64 > crate::files::MAX_FILE {
                return Err("block too large".into());
            }
            snap::raw::Decoder::new()
                .decompress_vec(data)
                .map_err(|e| format!("snappy: {e}"))
        }
        Some(other) => Err(format!("unknown block compression {other}")),
        None => Err("block trailer missing".into()),
    }
}

fn block_entries(block: &[u8]) -> Result<Vec<Entry>, String> {
    if block.len() < 4 {
        return Err("block too short".into());
    }
    let restarts = u32::from_le_bytes(block[block.len() - 4..].try_into().unwrap()) as usize;
    let end = block
        .len()
        .checked_sub(4 + restarts.checked_mul(4).ok_or("restarts overflow")?)
        .ok_or("bad restart count")?;
    let mut r = Reader::new(&block[..end]);
    let mut key: Vec<u8> = Vec::new();
    let mut out = Vec::new();
    while !r.done() {
        let shared = r.len()?;
        let unshared = r.len()?;
        let value_len = r.len()?;
        if shared > key.len() {
            return Err("bad shared key length".into());
        }
        key.truncate(shared);
        key.extend_from_slice(r.bytes(unshared)?);
        out.push((key.clone(), r.bytes(value_len)?.to_vec()));
    }
    Ok(out)
}

// --------------------------------------------------------------------- logs

const BLOCK: usize = 32 * 1024;
const HEADER: usize = 7;

/// The records of a log file (the write-ahead log or a manifest), put back
/// together from their fragments. A torn last record is dropped, as
/// LevelDB does on recovery.
fn log_records(file: &[u8]) -> Result<Vec<Vec<u8>>, String> {
    let mut out = Vec::new();
    let mut partial: Option<Vec<u8>> = None;
    for block in file.chunks(BLOCK) {
        let mut pos = 0;
        while pos + HEADER <= block.len() {
            let len = u16::from_le_bytes([block[pos + 4], block[pos + 5]]) as usize;
            let kind = block[pos + 6];
            if kind == 0 && len == 0 {
                // Preallocated, still zero: the rest of the block is empty.
                break;
            }
            let Some(data) = block.get(pos + HEADER..pos + HEADER + len) else {
                break;
            };
            pos += HEADER + len;
            match kind {
                1 => out.push(data.to_vec()),
                2 => partial = Some(data.to_vec()),
                3 => {
                    if let Some(p) = partial.as_mut() {
                        p.extend_from_slice(data)
                    }
                }
                4 => {
                    if let Some(mut p) = partial.take() {
                        p.extend_from_slice(data);
                        out.push(p);
                    }
                }
                other => return Err(format!("unknown log record type {other}")),
            }
        }
    }
    Ok(out)
}

/// A write batch: a sequence number, a count and that many puts or
/// deletions, numbered from the sequence on.
fn batch_entries(batch: &[u8]) -> Result<Vec<Change>, String> {
    let mut r = Reader::new(batch);
    let seq = r.u64_le()?;
    let count = r.u32_le()?;
    // Each entry takes three bytes or more: the count, read from the
    // file, never reserves more than that.
    let mut out = Vec::with_capacity((count as usize).min(r.rest().len() / 3));
    for i in 0..u64::from(count) {
        let kind = r.byte()?;
        let key = r.slice()?.to_vec();
        let value = match kind {
            VALUE => Some(r.slice()?.to_vec()),
            DELETION => None,
            other => return Err(format!("unknown batch entry {other}")),
        };
        out.push((key, seq + i, value));
    }
    Ok(out)
}

// ----------------------------------------------------------------- manifest

#[derive(Default)]
struct Version {
    files: BTreeSet<u64>,
    log: u64,
    prev_log: Option<u64>,
}

fn manifest_version(file: &[u8]) -> Result<Version, String> {
    let mut v = Version::default();
    for edit in log_records(file)? {
        let mut r = Reader::new(&edit);
        while !r.done() {
            match r.varint()? {
                1 => {
                    r.slice()?; // comparator name
                }
                2 => v.log = r.varint()?,
                3 | 4 => {
                    r.varint()?; // next file number, last sequence
                }
                5 => {
                    r.varint()?; // compact pointer: level and key
                    r.slice()?;
                }
                6 => {
                    r.varint()?;
                    let n = r.varint()?;
                    v.files.remove(&n);
                }
                7 => {
                    r.varint()?;
                    let n = r.varint()?;
                    r.varint()?; // size
                    r.slice()?; // smallest and largest keys
                    r.slice()?;
                    v.files.insert(n);
                }
                9 => v.prev_log = Some(r.varint()?),
                other => return Err(format!("unknown manifest tag {other}")),
            }
        }
    }
    Ok(v)
}

#[cfg(test)]
mod tests {
    use super::*;

    proptest::proptest! {
        /// A damaged or hostile LevelDB file is an error, never a panic.
        #[test]
        fn any_bytes_are_read_or_refused(bytes in proptest::collection::vec(proptest::prelude::any::<u8>(), 0..4096)) {
            let _ = table_entries(&bytes);
            let _ = log_records(&bytes);
            let _ = batch_entries(&bytes);
            let _ = manifest_version(&bytes);
            let _ = block_entries(&bytes);
            let _ = split_internal(&bytes);
        }
    }

    fn record(kind: u8, data: &[u8]) -> Vec<u8> {
        let mut out = vec![0, 0, 0, 0];
        out.extend_from_slice(&(data.len() as u16).to_le_bytes());
        out.push(kind);
        out.extend_from_slice(data);
        out
    }

    fn batch(seq: u64, entries: &[(&[u8], Option<&[u8]>)]) -> Vec<u8> {
        let mut out = seq.to_le_bytes().to_vec();
        out.extend_from_slice(&(entries.len() as u32).to_le_bytes());
        for (k, v) in entries {
            out.push(if v.is_some() { VALUE } else { DELETION });
            out.push(k.len() as u8);
            out.extend_from_slice(k);
            if let Some(v) = v {
                out.push(v.len() as u8);
                out.extend_from_slice(v);
            }
        }
        out
    }

    #[test]
    fn a_log_keeps_the_newest_and_hides_deletions() {
        let dir = tempfile::tempdir().unwrap();
        let mut log = record(1, &batch(1, &[(b"a", Some(b"1")), (b"b", Some(b"2"))]));
        // The second batch split in two fragments.
        let second = batch(3, &[(b"a", Some(b"3")), (b"b", None)]);
        let (first, last) = second.split_at(5);
        log.extend(record(2, first));
        log.extend(record(4, last));
        fs::write(dir.path().join("000003.log"), log).unwrap();
        let entries = read(dir.path()).unwrap();
        assert_eq!(entries, vec![(b"a".to_vec(), b"3".to_vec())]);
    }

    #[test]
    fn the_manifest_says_which_tables_and_logs_count() {
        let mut edit = vec![2, 5]; // log number 5
        edit.extend([7, 0, 4, 10, 1, b'a', 1, b'z']); // file 4 at level 0
        edit.extend([7, 0, 6, 10, 1, b'a', 1, b'z']); // file 6
        edit.extend([6, 0, 4]); // file 4 deleted
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("MANIFEST-000002"), record(1, &edit)).unwrap();
        fs::write(dir.path().join("CURRENT"), "MANIFEST-000002\n").unwrap();
        for name in ["000004.ldb", "000006.ldb", "000003.log", "000005.log"] {
            fs::write(dir.path().join(name), b"").unwrap();
        }
        let files = live_files(dir.path()).unwrap();
        let names = |v: &[PathBuf]| -> Vec<String> {
            v.iter()
                .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
                .collect()
        };
        assert_eq!(names(&files.tables), ["000006.ldb"]);
        assert_eq!(names(&files.logs), ["000005.log"]);
    }

    /// A block with these entries and one restart point.
    fn make_block(entries: &[(Vec<u8>, Vec<u8>)]) -> Vec<u8> {
        let mut block = Vec::new();
        for (k, v) in entries {
            block.extend([0, k.len() as u8, v.len() as u8]);
            block.extend_from_slice(k);
            block.extend_from_slice(v);
        }
        block.extend(0u32.to_le_bytes());
        block.extend(1u32.to_le_bytes());
        block
    }

    #[test]
    fn a_table_file_with_an_index_and_a_compressed_block() {
        let internal = |k: &[u8], seq: u64, kind: u8| {
            let mut key = k.to_vec();
            key.extend(((seq << 8) | u64::from(kind)).to_le_bytes());
            key
        };
        let data = make_block(&[
            (internal(b"a", 5, VALUE), b"one".to_vec()),
            (internal(b"b", 6, DELETION), Vec::new()),
        ]);
        let compressed = snap::raw::Encoder::new().compress_vec(&data).unwrap();
        let mut file = compressed.clone();
        file.extend([1, 0, 0, 0, 0]); // snappy, then a checksum
        let handle = |offset: usize, size: usize| vec![offset as u8, size as u8];
        let index = make_block(&[(internal(b"b", 6, DELETION), handle(0, compressed.len()))]);
        let index_at = file.len();
        file.extend(&index);
        file.extend([0, 0, 0, 0, 0]);
        let mut footer = handle(0, 0); // no metaindex
        footer.extend(handle(index_at, index.len()));
        footer.resize(40, 0);
        footer.extend(TABLE_MAGIC.to_le_bytes());
        file.extend(footer);
        let dir = tempfile::tempdir().unwrap();
        fs::write(dir.path().join("000005.ldb"), file).unwrap();
        // A later log puts b back.
        let log = record(1, &batch(9, &[(b"b", Some(b"two"))]));
        fs::write(dir.path().join("000006.log"), log).unwrap();
        let mut entries = read(dir.path()).unwrap();
        entries.sort();
        assert_eq!(
            entries,
            vec![
                (b"a".to_vec(), b"one".to_vec()),
                (b"b".to_vec(), b"two".to_vec())
            ]
        );
    }

    #[test]
    fn a_block_with_shared_key_prefixes() {
        let mut block = Vec::new();
        for (shared, rest, value) in [(0u8, &b"apple"[..], &b"1"[..]), (2, b"ricot", b"2")] {
            block.extend([shared, rest.len() as u8, value.len() as u8]);
            block.extend_from_slice(rest);
            block.extend_from_slice(value);
        }
        block.extend(0u32.to_le_bytes()); // restart point at 0
        block.extend(1u32.to_le_bytes());
        let entries = block_entries(&block).unwrap();
        assert_eq!(
            entries,
            vec![
                (b"apple".to_vec(), b"1".to_vec()),
                (b"apricot".to_vec(), b"2".to_vec())
            ]
        );
    }
}
