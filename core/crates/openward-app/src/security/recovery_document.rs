//! Self-contained A4 PDF: ASCII text and vector QR, no network/fonts/temp image.
use openward_crypto::unlock::RecoveryKit;
use openward_vault::{Error, Result};
use qrcodegen::{QrCode, QrCodeEcc};
use std::fmt::Write;
use zeroize::Zeroizing;

fn code(kit: &RecoveryKit) -> Result<QrCode> {
    QrCode::encode_text(&kit.text(), QrCodeEcc::Quartile)
        .map_err(|_| Error::Invalid("recovery QR too large"))
}
/// Square row-major modules, with a four-module quiet border. The length is
/// always a perfect square; no identifiers or device details are included.
pub(super) fn qr(kit: &RecoveryKit) -> Result<Vec<u8>> {
    let qr = code(kit)?;
    let n = qr.size() + 8;
    Ok((0..n * n)
        .map(|i| u8::from(qr.get_module(i % n - 4, i / n - 4)))
        .collect())
}
pub(super) fn pdf(kit: &RecoveryKit) -> Result<Zeroizing<Vec<u8>>> {
    let qr = code(kit)?;
    let text = kit.text();
    let groups: Vec<_> = text.split('-').collect();
    let mut stream = Zeroizing::new(String::new());
    fn line(s: &mut String, font: &str, size: u32, y: u32, text: &str) {
        // All input is fixed ASCII or validated hex kit groups, never arbitrary
        // user text. Parentheses/backslashes cannot enter PDF string syntax.
        writeln!(s, "BT /{font} {size} Tf 48 {y} Td ({text}) Tj ET").unwrap();
    }
    line(
        &mut stream,
        "F1",
        18,
        780,
        "OpenWard - Recovery kit / Kit de recuperacion",
    );
    line(
        &mut stream,
        "F1",
        11,
        746,
        "Keep this sheet private, away from the computer and its backups.",
    );
    line(
        &mut stream,
        "F1",
        11,
        728,
        "Guarda esta hoja en privado, separada del equipo y sus copias.",
    );
    line(&mut stream, "F2", 16, 688, "OWRK1-");
    for (i, row) in groups[1..17].chunks(4).enumerate() {
        let mut row_text = Zeroizing::new(String::new());
        for group in row {
            write!(&mut *row_text, "{group}-").unwrap();
        }
        line(&mut stream, "F2", 18, 656 - i as u32 * 28, &row_text);
    }
    line(&mut stream, "F2", 12, 536, groups[17]);
    line(
        &mut stream,
        "F1",
        10,
        510,
        "Activate this kit in OpenWard by confirming groups 3 and 12 before use.",
    );
    line(
        &mut stream,
        "F1",
        10,
        492,
        "Activa el kit en OpenWard confirmando los grupos 3 y 12 antes de usarlo.",
    );
    // QR contains the exact complete OWRK1 string, not a URL. White quiet zone.
    let n = qr.size();
    let scale = 4;
    let x = (595 - n * scale) / 2;
    for row in 0..n {
        for col in 0..n {
            if qr.get_module(col, row) {
                writeln!(
                    &mut *stream,
                    "{} {} {scale} {scale} re f",
                    x + col * scale,
                    292 + (n - 1 - row) * scale
                )
                .unwrap();
            }
        }
    }
    line(
        &mut stream,
        "F1",
        11,
        250,
        "This kit unlocks the local vault without its password. Do not share it.",
    );
    line(
        &mut stream,
        "F1",
        11,
        232,
        "Este kit abre el vault local sin contrasena. No lo compartas.",
    );
    line(
        &mut stream,
        "F1",
        11,
        204,
        "The kit does not contain your data. Keep an encrypted vault backup too.",
    );
    line(
        &mut stream,
        "F1",
        11,
        186,
        "El kit no contiene tus datos. Conserva tambien una copia cifrada del vault.",
    );
    line(
        &mut stream,
        "F1",
        11,
        158,
        "Regeneration revokes the previous kit for the updated vault only.",
    );
    line(
        &mut stream,
        "F1",
        11,
        140,
        "La regeneracion no revoca kits en copias antiguas del vault.",
    );
    line(
        &mut stream,
        "F1",
        10,
        88,
        "On the lock screen, choose Recovery kit and type or paste the full code.",
    );
    line(
        &mut stream,
        "F1",
        10,
        70,
        "En la pantalla de bloqueo, elige Kit de recuperacion e introduce el codigo.",
    );
    let objects = vec![
        "<< /Type /Catalog /Pages 2 0 R >>".to_owned(),
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_owned(),
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>".to_owned(),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".to_owned(),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>".to_owned(),
        format!("<< /Length {} >>\nstream\n{}endstream",stream.len(),*stream),
    ];
    let objects = Zeroizing::new(objects);
    let mut out = Zeroizing::new(b"%PDF-1.4\n".to_vec());
    let mut offsets = vec![0usize];
    for (i, object) in objects.iter().enumerate() {
        offsets.push(out.len());
        let encoded = Zeroizing::new(format!("{} 0 obj\n{}\nendobj\n", i + 1, object));
        out.extend(encoded.as_bytes());
    }
    let xref = out.len();
    out.extend(format!("xref\n0 {}\n0000000000 65535 f \n", offsets.len()).as_bytes());
    for offset in &offsets[1..] {
        out.extend(format!("{offset:010} 00000 n \n").as_bytes());
    }
    out.extend(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n",
            offsets.len()
        )
        .as_bytes(),
    );
    Ok(out)
}
