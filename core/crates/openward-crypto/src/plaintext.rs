//! S4 field-clock plaintext. D3's single writer seeds a complete snapshot;
//! v0.5 can use the same fields/clocks/unset shape for per-field changes.
use crate::{Error, envelope::MAX_PLAINTEXT, wire};

/// Extract bytes without decoding/normalizing unknown Body fields. Unsupported
/// outer v0 forms abort migration; the original database remains intact.
pub fn legacy_body(bytes: &[u8]) -> Result<&[u8], Error> {
    if bytes.len() > MAX_PLAINTEXT + 128 {
        return Err(Error::Limit);
    }
    let mut r = wire::Reader::new(bytes);
    if r.number(5)? != 2 {
        return Err(Error::Encoding);
    }
    let mut version = None;
    let mut body = None;
    for _ in 0..2 {
        match r.text(4)? {
            "v" if version.is_none() => version = Some(r.number(0)?),
            "body" if body.is_none() => body = Some(r.bytes(MAX_PLAINTEXT - 128)?),
            _ => return Err(Error::Encoding),
        }
    }
    if !r.done() {
        return Err(Error::Encoding);
    }
    match version {
        Some(0) => body.ok_or(Error::Encoding),
        Some(v) => Err(Error::Version(v)),
        None => Err(Error::Encoding),
    }
}
pub fn snapshot(body: &[u8], hlc: u64) -> Result<Vec<u8>, Error> {
    if body.len() > MAX_PLAINTEXT - 128 {
        return Err(Error::Limit);
    }
    let mut out = Vec::with_capacity(body.len() + 128);
    wire::number(&mut out, 5, 5);
    wire::key(&mut out, "hlc");
    wire::number(&mut out, 0, hlc);
    wire::key(&mut out, "base");
    wire::number(&mut out, 0, hlc);
    wire::key(&mut out, "body");
    wire::bytes(&mut out, body);
    for name in ["unset", "clocks"] {
        wire::key(&mut out, name);
        wire::number(&mut out, 5, 0);
    }
    Ok(out)
}
pub fn body(bytes: &[u8]) -> Result<(u64, &[u8]), Error> {
    if bytes.len() > MAX_PLAINTEXT {
        return Err(Error::Limit);
    }
    let mut r = wire::Reader::new(bytes);
    if r.number(5)? != 5 {
        return Err(Error::Encoding);
    }
    r.key("hlc")?;
    let hlc = r.number(0)?;
    r.key("base")?;
    if r.number(0)? > hlc {
        return Err(Error::Encoding);
    }
    r.key("body")?;
    let body = r.bytes(MAX_PLAINTEXT - 128)?;
    for name in ["unset", "clocks"] {
        r.key(name)?;
        let count = r.number(5)?;
        if count > 65536 {
            return Err(Error::Limit);
        }
        let mut previous: Option<&str> = None;
        for _ in 0..count {
            let field = r.text(4096)?;
            if previous.is_some_and(|p| (p.len(), p.as_bytes()) >= (field.len(), field.as_bytes()))
            {
                return Err(Error::Encoding);
            }
            previous = Some(field);
            if r.number(0)? > hlc {
                return Err(Error::Encoding);
            }
        }
    }
    if !r.done() {
        return Err(Error::Encoding);
    }
    Ok((hlc, body))
}
