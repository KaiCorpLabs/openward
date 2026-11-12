//! Small bounded binary records for keys; item envelopes retain canonical CBOR.
use crate::Error;
pub(crate) struct Reader<'a>(&'a [u8]);
impl<'a> Reader<'a> {
    pub fn new(bytes: &'a [u8], magic: &[u8; 4]) -> Result<Self, Error> {
        let mut r = Self(bytes);
        if r.take(4)? != magic {
            return Err(Error::Encoding);
        }
        let v = r.u8()?;
        if v != 1 {
            return Err(Error::Version(v.into()));
        }
        Ok(r)
    }
    pub fn take(&mut self, n: usize) -> Result<&'a [u8], Error> {
        if n > self.0.len() {
            return Err(Error::Encoding);
        }
        let (head, tail) = self.0.split_at(n);
        self.0 = tail;
        Ok(head)
    }
    pub fn fixed<const N: usize>(&mut self) -> Result<[u8; N], Error> {
        Ok(self.take(N)?.try_into().unwrap())
    }
    pub fn u8(&mut self) -> Result<u8, Error> {
        Ok(self.take(1)?[0])
    }
    pub fn u32(&mut self) -> Result<u32, Error> {
        Ok(u32::from_be_bytes(self.fixed()?))
    }
    pub fn blob(&mut self, max: usize) -> Result<&'a [u8], Error> {
        let n = u16::from_be_bytes(self.fixed()?) as usize;
        if n > max {
            return Err(Error::Limit);
        }
        self.take(n)
    }
    pub fn finish(self) -> Result<(), Error> {
        if self.0.is_empty() {
            Ok(())
        } else {
            Err(Error::Encoding)
        }
    }
}
pub(crate) fn record(magic: &[u8; 4]) -> Vec<u8> {
    [magic.as_slice(), &[1]].concat()
}
pub(crate) fn blob(out: &mut Vec<u8>, bytes: &[u8]) {
    out.extend(
        u16::try_from(bytes.len())
            .expect("bounded key record")
            .to_be_bytes(),
    );
    out.extend(bytes);
}
