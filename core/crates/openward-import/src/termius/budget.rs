//! One cumulative allocation/work budget for a complete foreign database.
use std::fs;
use std::io::{self, Read};
use std::path::Path;

pub(super) const MAX_DEPTH: usize = 64;
pub(super) const MAX_ARRAY: usize = 65_536;

pub(super) struct Budget {
    bytes: usize,
    work: usize,
    files: usize,
    pub exhausted: bool,
}

impl Default for Budget {
    fn default() -> Self {
        Self {
            bytes: 256 << 20,
            work: 1_000_000,
            files: 4096,
            exhausted: false,
        }
    }
}

impl Budget {
    #[cfg(test)]
    pub fn limited(bytes: usize, work: usize, files: usize) -> Self {
        Self {
            bytes,
            work,
            files,
            exhausted: false,
        }
    }

    pub fn refuse<T>(&mut self) -> Result<T, String> {
        self.exhausted = true;
        Err("Termius import exceeds its resource budget".into())
    }

    pub fn bytes(&mut self, n: usize) -> Result<(), String> {
        match self.bytes.checked_sub(n) {
            Some(left) => {
                self.bytes = left;
                Ok(())
            }
            None => self.refuse(),
        }
    }

    pub fn work(&mut self, n: usize) -> Result<(), String> {
        match self.work.checked_sub(n) {
            Some(left) => {
                self.work = left;
                Ok(())
            }
            None => self.refuse(),
        }
    }

    pub fn allocation(&mut self, count: usize, size: usize) -> Result<(), String> {
        self.work(count)?;
        self.buffer(count, size)
    }

    pub fn buffer(&mut self, count: usize, size: usize) -> Result<(), String> {
        let Some(bytes) = count.checked_mul(size) else {
            return self.refuse();
        };
        self.bytes(bytes)
    }

    pub fn read(&mut self, path: &Path) -> io::Result<Vec<u8>> {
        self.entry().map_err(invalid)?;
        if !fs::metadata(path)?.is_file() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "not a file"));
        }
        let file = fs::File::open(path)?;
        if !file.metadata()?.is_file() {
            return Err(io::Error::new(io::ErrorKind::InvalidInput, "not a file"));
        }
        let limit = self.bytes.min(crate::files::MAX_FILE as usize);
        let mut out = Vec::new();
        file.take(limit as u64 + 1).read_to_end(&mut out)?;
        if out.len() > limit {
            return self.refuse().map_err(invalid);
        }
        self.bytes(out.len()).map_err(invalid)?;
        Ok(out)
    }

    pub fn entry(&mut self) -> Result<(), String> {
        if self.files == 0 {
            return self.refuse();
        }
        self.files -= 1;
        self.work(1)
    }
}

pub(super) fn invalid(error: String) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, error)
}
