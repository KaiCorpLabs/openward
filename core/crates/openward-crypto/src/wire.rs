//! Only the schema's definite-length canonical CBOR forms. Declared lengths
//! are checked against both remaining input and protocol limits before copying.
use crate::Error;

pub fn number(out: &mut Vec<u8>, major: u8, n: u64) {
    match n {
        0..=23 => out.push((major << 5) | n as u8),
        24..=255 => out.extend([(major << 5) | 24, n as u8]),
        256..=65535 => {
            out.push((major << 5) | 25);
            out.extend((n as u16).to_be_bytes());
        }
        65536..=4294967295 => {
            out.push((major << 5) | 26);
            out.extend((n as u32).to_be_bytes());
        }
        _ => {
            out.push((major << 5) | 27);
            out.extend(n.to_be_bytes());
        }
    }
}
pub fn bytes(out: &mut Vec<u8>, bytes: &[u8]) {
    number(out, 2, bytes.len() as u64);
    out.extend(bytes);
}
pub fn key(out: &mut Vec<u8>, key: &str) {
    number(out, 3, key.len() as u64);
    out.extend(key.as_bytes());
}

pub struct Reader<'a> {
    data: &'a [u8],
    at: usize,
}
impl<'a> Reader<'a> {
    pub fn new(data: &'a [u8]) -> Self {
        Self { data, at: 0 }
    }
    fn take(&mut self, n: usize) -> Result<&'a [u8], Error> {
        let end = self.at.checked_add(n).ok_or(Error::Encoding)?;
        let bytes = self.data.get(self.at..end).ok_or(Error::Encoding)?;
        self.at = end;
        Ok(bytes)
    }
    pub fn number(&mut self, major: u8) -> Result<u64, Error> {
        let tag = self.take(1)?[0];
        if tag >> 5 != major {
            return Err(Error::Encoding);
        }
        let n = tag & 31;
        let (value, minimum) = match n {
            0..=23 => return Ok(u64::from(n)),
            24 => (u64::from(self.take(1)?[0]), 24),
            25 => (
                u64::from(u16::from_be_bytes(self.take(2)?.try_into().unwrap())),
                256,
            ),
            26 => (
                u64::from(u32::from_be_bytes(self.take(4)?.try_into().unwrap())),
                65536,
            ),
            27 => (
                u64::from_be_bytes(self.take(8)?.try_into().unwrap()),
                4294967296,
            ),
            _ => return Err(Error::Encoding),
        };
        if value < minimum {
            return Err(Error::Encoding);
        }
        Ok(value)
    }
    pub fn key(&mut self, expected: &str) -> Result<(), Error> {
        if self.number(3)? != expected.len() as u64
            || self.take(expected.len())? != expected.as_bytes()
        {
            return Err(Error::Encoding);
        }
        Ok(())
    }
    pub fn bytes(&mut self, limit: usize) -> Result<&'a [u8], Error> {
        let n = usize::try_from(self.number(2)?).map_err(|_| Error::Limit)?;
        if n > limit {
            return Err(Error::Limit);
        }
        self.take(n)
    }
    pub fn text(&mut self, limit: usize) -> Result<&'a str, Error> {
        let n = usize::try_from(self.number(3)?).map_err(|_| Error::Limit)?;
        if n > limit {
            return Err(Error::Limit);
        }
        std::str::from_utf8(self.take(n)?).map_err(|_| Error::Encoding)
    }
    pub fn fixed<const N: usize>(&mut self) -> Result<[u8; N], Error> {
        self.bytes(N)?.try_into().map_err(|_| Error::Encoding)
    }
    pub fn done(&self) -> bool {
        self.at == self.data.len()
    }
}
