//! One cumulative allocation/work budget for a complete foreign database.
use std::cell::Cell;
use std::fs;
use std::io::{self, Read};
use std::path::Path;
use std::rc::Rc;

pub(super) const MAX_DEPTH: usize = 64;
pub(super) const MAX_ARRAY: usize = 65_536;

#[derive(Clone)]
pub(super) struct Budget(Rc<Remaining>);

struct Remaining {
    bytes: Cell<usize>,
    work: Cell<usize>,
    files: Cell<usize>,
    exhausted: Cell<bool>,
}

impl Default for Budget {
    fn default() -> Self {
        Self::new(256 << 20, 1_000_000, 4096)
    }
}

impl Budget {
    fn new(bytes: usize, work: usize, files: usize) -> Self {
        Self(Rc::new(Remaining {
            bytes: bytes.into(),
            work: work.into(),
            files: files.into(),
            exhausted: false.into(),
        }))
    }
    #[cfg(test)]
    pub fn limited(bytes: usize, work: usize, files: usize) -> Self {
        Self::new(bytes, work, files)
    }

    pub fn exhausted(&self) -> bool {
        self.0.exhausted.get()
    }

    pub fn refuse<T>(&self) -> Result<T, String> {
        self.0.exhausted.set(true);
        Err("Termius import exceeds its resource budget".into())
    }

    pub fn bytes(&self, n: usize) -> Result<(), String> {
        if self.exhausted() {
            return self.refuse();
        }
        match self.0.bytes.get().checked_sub(n) {
            Some(left) => {
                self.0.bytes.set(left);
                Ok(())
            }
            None => self.refuse(),
        }
    }

    pub fn work(&self, n: usize) -> Result<(), String> {
        if self.exhausted() {
            return self.refuse();
        }
        match self.0.work.get().checked_sub(n) {
            Some(left) => {
                self.0.work.set(left);
                Ok(())
            }
            None => self.refuse(),
        }
    }

    pub fn allocation(&self, count: usize, size: usize) -> Result<(), String> {
        self.work(count)?;
        self.buffer(count, size)
    }

    pub fn buffer(&self, count: usize, size: usize) -> Result<(), String> {
        let Some(bytes) = count.checked_mul(size) else {
            return self.refuse();
        };
        self.bytes(bytes)
    }

    pub fn read(&self, path: &Path) -> io::Result<Vec<u8>> {
        self.entry().map_err(invalid)?;
        if !fs::metadata(path)?.is_file() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "not a file"));
        }
        let file = fs::File::open(path)?;
        if !file.metadata()?.is_file() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "not a file"));
        }
        let limit = self.0.bytes.get().min(crate::files::MAX_FILE as usize);
        let mut out = Vec::new();
        file.take(limit as u64 + 1).read_to_end(&mut out)?;
        if out.len() > limit {
            return self.refuse().map_err(invalid);
        }
        self.bytes(out.len()).map_err(invalid)?;
        Ok(out)
    }

    pub fn entry(&self) -> Result<(), String> {
        if self.0.files.get() == 0 {
            return self.refuse();
        }
        self.0.files.set(self.0.files.get() - 1);
        self.work(1)
    }
}

pub(super) fn invalid(error: String) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error)
}
