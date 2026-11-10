//! Randomness that is not: the bytes a test vector says, in order.

use rand_core::{Infallible, TryCryptoRng, TryRng};

/// Gives `bytes` as its randomness, and panics if asked for more: a
/// vector's `ikmE` or `eseed`, so that a library's sender reproduces it.
pub struct Fixed {
    bytes: Vec<u8>,
    at: usize,
}

impl Fixed {
    pub fn new(bytes: &[u8]) -> Self {
        Self {
            bytes: bytes.to_vec(),
            at: 0,
        }
    }

    /// Whether all of it was used: a library that drew less than the
    /// vector gives did not use it as the draft says.
    pub fn used_up(&self) -> bool {
        self.at == self.bytes.len()
    }
}

impl TryRng for Fixed {
    type Error = Infallible;

    fn try_next_u32(&mut self) -> Result<u32, Infallible> {
        let mut b = [0; 4];
        self.try_fill_bytes(&mut b)?;
        Ok(u32::from_le_bytes(b))
    }

    fn try_next_u64(&mut self) -> Result<u64, Infallible> {
        let mut b = [0; 8];
        self.try_fill_bytes(&mut b)?;
        Ok(u64::from_le_bytes(b))
    }

    fn try_fill_bytes(&mut self, dst: &mut [u8]) -> Result<(), Infallible> {
        let end = self.at + dst.len();
        assert!(
            end <= self.bytes.len(),
            "asked for {end} bytes of randomness; the vector has {}",
            self.bytes.len()
        );
        dst.copy_from_slice(&self.bytes[self.at..end]);
        self.at = end;
        Ok(())
    }
}

impl TryCryptoRng for Fixed {}
