//! Text files as other programs write them: UTF-16 with a byte order mark
//! (Windows' registry exports), UTF-8 (with or without one), or the
//! Windows code page (Windows-1252) when the bytes are not UTF-8.

pub fn decode(bytes: &[u8]) -> String {
    match bytes {
        [0xff, 0xfe, rest @ ..] => utf16(rest, u16::from_le_bytes),
        [0xfe, 0xff, rest @ ..] => utf16(rest, u16::from_be_bytes),
        [0xef, 0xbb, 0xbf, rest @ ..] => String::from_utf8_lossy(rest).into_owned(),
        _ => match std::str::from_utf8(bytes) {
            Ok(s) => s.to_owned(),
            Err(_) => bytes.iter().map(|&b| windows_1252(b)).collect(),
        },
    }
}

fn utf16(bytes: &[u8], unit: fn([u8; 2]) -> u16) -> String {
    let units: Vec<u16> = bytes.as_chunks::<2>().0.iter().map(|c| unit(*c)).collect();
    String::from_utf16_lossy(&units)
}

/// Windows-1252: Latin-1 but for 0x80–0x9F.
fn windows_1252(b: u8) -> char {
    const HIGH: [char; 32] = [
        '€', '\u{81}', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '\u{8d}', 'Ž',
        '\u{8f}', '\u{90}', '‘', '’', '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', '\u{9d}',
        'ž', 'Ÿ',
    ];
    match b {
        0x80..=0x9f => HIGH[(b - 0x80) as usize],
        _ => b as char,
    }
}

/// `%XX` escapes undone, the bytes then decoded like a file.
pub fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let hex = |c: u8| (c as char).to_digit(16).map(|d| d as u8);
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%'
            && let (Some(Some(h)), Some(Some(l))) =
                (b.get(i + 1).map(|&c| hex(c)), b.get(i + 2).map(|&c| hex(c)))
        {
            out.push(h << 4 | l);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    decode(&out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf16_utf8_and_the_windows_code_page() {
        let mut le = vec![0xff, 0xfe];
        le.extend("Señor".encode_utf16().flat_map(|u| u.to_le_bytes()));
        assert_eq!(decode(&le), "Señor");
        assert_eq!(decode("Señor".as_bytes()), "Señor");
        assert_eq!(decode(b"Se\xf1or \x80"), "Señor €");
    }

    #[test]
    fn percent_escapes() {
        assert_eq!(percent_decode("prod%20web"), "prod web");
        assert_eq!(percent_decode("100%"), "100%");
        assert_eq!(percent_decode("caf%C3%A9"), "café");
        assert_eq!(percent_decode("caf%E9"), "café");
        assert_eq!(percent_decode("%zz"), "%zz");
    }
}
