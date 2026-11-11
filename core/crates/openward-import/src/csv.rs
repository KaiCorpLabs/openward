//! Hosts from a CSV file: Termius's import template, or any spreadsheet
//! with one host per row and a header naming the columns.
//!
//! Columns are recognized by their header, in English or Spanish and
//! whatever their case or punctuation (`Hostname/IP`, `host`, `Dirección`);
//! the others are left out. The fields are separated by commas,
//! semicolons (a spreadsheet in Spanish saves those) or tabs, quoted as
//! RFC 4180 says. Groups nest with `/` or `\`; tags are separated by
//! commas or semicolons inside their cell. Passwords are counted, never
//! read.

use std::collections::BTreeSet;

use openward_proto::Settings;

use crate::bundle::{Bundle, Group, Host, KeyRef, StoredKey, Warning, WarningKind};
use crate::text;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Column {
    Label,
    Address,
    Port,
    User,
    Group,
    Subgroup,
    Tags,
    Protocol,
    Password,
    Key,
    Notes,
}

/// A header cell as a column: lowercase letters and digits only, so
/// `Hostname/IP` is `hostnameip`.
fn column(header: &str) -> Option<Column> {
    let key: String = header
        .chars()
        .flat_map(char::to_lowercase)
        .map(|c| match c {
            'á' => 'a',
            'é' => 'e',
            'í' => 'i',
            'ó' => 'o',
            'ú' => 'u',
            'ñ' => 'n',
            c => c,
        })
        .filter(char::is_ascii_alphanumeric)
        .collect();
    Some(match key.as_str() {
        "label" | "name" | "alias" | "title" | "nombre" | "etiqueta" | "titulo" => Column::Label,
        "hostnameip" | "hostname" | "host" | "address" | "ip" | "ipaddress" | "server"
        | "direccion" | "servidor" | "hostip" => Column::Address,
        "port" | "puerto" => Column::Port,
        "username" | "user" | "login" | "usuario" => Column::User,
        "groups" | "group" | "folder" | "path" | "grupo" | "grupos" | "carpeta" => Column::Group,
        "subgroups" | "subgroup" | "subgrupo" | "subgrupos" => Column::Subgroup,
        "tags" | "tag" | "etiquetas" => Column::Tags,
        "protocol" | "type" | "protocolo" | "tipo" => Column::Protocol,
        "password" | "pass" | "contrasena" | "clave" => Column::Password,
        "sshkey" | "key" | "privatekey" | "identityfile" | "keyfile" | "clavessh"
        | "claveprivada" => Column::Key,
        "notes" | "note" | "description" | "comment" | "notas" | "descripcion" | "comentario" => {
            Column::Notes
        }
        _ => return None,
    })
}

/// The separator the header uses most, outside quotes.
fn separator(header: &str) -> char {
    let mut quoted = false;
    let mut counts = [(',', 0), (';', 0), ('\t', 0)];
    for c in header.chars() {
        if c == '"' {
            quoted = !quoted;
        } else if !quoted && let Some(n) = counts.iter_mut().find(|(s, _)| *s == c) {
            n.1 += 1;
        }
    }
    counts
        .iter()
        .max_by_key(|(_, n)| *n)
        .map_or(',', |(s, _)| *s)
}

/// The rows of `text`, each a list of fields. A quoted field may hold the
/// separator, newlines and `""` for a quote.
fn rows(text: &str, sep: char) -> Vec<Vec<String>> {
    let mut out = Vec::new();
    let mut row = Vec::new();
    let mut field = String::new();
    let mut quoted = false;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            match c {
                '"' if chars.peek() == Some(&'"') => {
                    chars.next();
                    field.push('"');
                }
                '"' => quoted = false,
                '\r' if chars.peek() == Some(&'\n') => {}
                c => field.push(c),
            }
            continue;
        }
        match c {
            '"' if field.trim().is_empty() => {
                field.clear();
                quoted = true;
            }
            c if c == sep => row.push(std::mem::take(&mut field)),
            '\r' => {}
            '\n' => {
                row.push(std::mem::take(&mut field));
                out.push(std::mem::take(&mut row));
            }
            c => field.push(c),
        }
    }
    if !field.is_empty() || !row.is_empty() {
        row.push(field);
        out.push(row);
    }
    out.retain(|r| r.iter().any(|f| !f.trim().is_empty()));
    out
}

/// The header's columns, in order; None if it names no address.
fn header(text: &str) -> Option<(char, Vec<Option<Column>>)> {
    let first = text.lines().find(|l| !l.trim().is_empty())?;
    let sep = separator(first);
    let columns: Vec<Option<Column>> = rows(first, sep)
        .first()?
        .iter()
        .map(|h| column(h))
        .collect();
    columns
        .contains(&Some(Column::Address))
        .then_some((sep, columns))
}

/// Whether the text is a CSV of hosts: its header names an address.
pub fn sniff(text: &str) -> bool {
    header(text).is_some_and(|(_, c)| c.iter().flatten().count() >= 2)
}

pub fn parse(bytes: &[u8]) -> Result<Bundle, String> {
    let text = text::decode(bytes);
    let (sep, columns) = header(&text).ok_or("the header names no host or IP column")?;
    let mut out = Bundle::default();
    let mut groups = BTreeSet::new();
    let mut seen = BTreeSet::new();
    for (n, row) in rows(&text, sep).into_iter().enumerate().skip(1) {
        let get = |col: Column| -> &str {
            columns
                .iter()
                .position(|c| *c == Some(col))
                .and_then(|i| row.get(i))
                .map_or("", |s| s.trim())
        };
        let address = get(Column::Address);
        let label = Some(get(Column::Label))
            .filter(|l| !l.is_empty())
            .unwrap_or(address)
            .to_owned();
        if address.is_empty() {
            if !label.is_empty() {
                out.warnings.push(Warning::about(
                    &label,
                    WarningKind::BadValue {
                        field: "hostname".into(),
                        value: String::new(),
                    },
                ));
            }
            continue;
        }
        if !get(Column::Password).is_empty() {
            out.passwords += 1;
        }

        let mut settings = Settings::default();
        let port = get(Column::Port);
        if !port.is_empty() {
            match port.parse::<u16>() {
                Ok(p) if p > 0 => settings.port = (p != 22).then_some(p),
                _ => out.warnings.push(Warning::about(
                    &label,
                    WarningKind::BadValue {
                        field: "port".into(),
                        value: port.into(),
                    },
                )),
            }
        }
        let user = get(Column::User);
        settings.user = (!user.is_empty()).then(|| user.to_owned());

        // `a/b` in Groups, and Subgroups under it.
        let mut path: Vec<String> = Vec::new();
        for cell in [get(Column::Group), get(Column::Subgroup)] {
            path.extend(
                cell.split(['/', '\\'])
                    .map(str::trim)
                    .filter(|p| !p.is_empty())
                    .map(str::to_owned),
            );
        }
        for depth in 1..=path.len() {
            let id = path[..depth].join("/");
            if groups.insert(id.clone()) {
                out.groups.push(Group {
                    id,
                    name: path[depth - 1].clone(),
                    parent: (depth > 1).then(|| path[..depth - 1].join("/")),
                    ..Group::default()
                });
            }
        }
        let group = (!path.is_empty()).then(|| path.join("/"));

        let mut keys = Vec::new();
        let key = get(Column::Key);
        if key.contains("PRIVATE KEY") || key.starts_with("PuTTY-User-Key-File") {
            let id = format!("row{n}");
            out.keys.push(StoredKey {
                id: id.clone(),
                label: label.clone(),
                private_key: key.to_owned().into(),
                passphrase: None,
            });
            keys.push(KeyRef::Stored(id));
        } else if !key.is_empty() && !key.contains(char::is_whitespace) {
            keys.push(KeyRef::Path(key.to_owned()));
        }

        let protocol = get(Column::Protocol).to_lowercase();
        let unsupported = match protocol.as_str() {
            "" | "ssh" | "ssh2" | "sftp" => None,
            "mosh" => {
                out.warnings.push(Warning::about(&label, WarningKind::Mosh));
                None
            }
            "telnet" => {
                settings.protocol = Some(openward_proto::Protocol::Telnet);
                None
            }
            // The address is the port; the line, OpenWard's default.
            "serial" | "serie" => {
                settings.protocol = Some(openward_proto::Protocol::Serial);
                settings.port = None;
                None
            }
            other => Some(other.to_owned()),
        };

        let notes = get(Column::Notes);
        // Same group, name and address: the same host on the next import.
        let id = format!(
            "{}|{label}|{address}:{}",
            group.as_deref().unwrap_or(""),
            settings.port.unwrap_or(22)
        );
        if !seen.insert(id.clone()) {
            continue;
        }
        out.hosts.push(Host {
            id,
            label,
            address: address.to_owned(),
            group,
            settings,
            identity: None,
            keys,
            jumps: Vec::new(),
            tags: get(Column::Tags)
                .split([',', ';'])
                .map(str::trim)
                .filter(|t| !t.is_empty())
                .map(str::to_owned)
                .collect(),
            notes: (!notes.is_empty()).then(|| notes.to_owned()),
            unsupported,
        });
    }
    if out.hosts.is_empty() && out.warnings.is_empty() {
        return Err("no host in the file".into());
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn termius_template() {
        let csv = "Groups,Label,Tags,Hostname/IP,Protocol,Port,Username,Password\n\
                   Producción/Web,web-1,\"prod, nginx\",10.0.0.1,ssh,22,deploy,secreto\n\
                   Producción,db,,db.example.com,ssh,2222,postgres,\n\
                   ,router,,192.168.1.1,telnet,23,admin,\n";
        assert!(sniff(csv));
        let b = parse(csv.as_bytes()).unwrap();
        assert_eq!(b.passwords, 1);
        let names: Vec<_> = b
            .groups
            .iter()
            .map(|g| (g.id.as_str(), g.parent.as_deref()))
            .collect();
        assert_eq!(
            names,
            [("Producción", None), ("Producción/Web", Some("Producción"))]
        );
        assert_eq!(b.hosts.len(), 3);
        let web = &b.hosts[0];
        assert_eq!(web.label, "web-1");
        assert_eq!(web.address, "10.0.0.1");
        assert_eq!(web.group.as_deref(), Some("Producción/Web"));
        assert_eq!(web.tags, ["prod", "nginx"]);
        assert_eq!(web.settings.user.as_deref(), Some("deploy"));
        assert_eq!(web.settings.port, None, "22 is the default");
        assert_eq!(b.hosts[1].settings.port, Some(2222));
        assert_eq!(b.hosts[2].unsupported, None);
        assert_eq!(
            b.hosts[2].settings.protocol,
            Some(openward_proto::Protocol::Telnet)
        );
        assert_eq!(b.hosts[2].settings.port, Some(23));
        assert_eq!(b.hosts[2].group, None);
    }

    #[test]
    fn a_spreadsheet_in_spanish() {
        // Semicolons, a byte order mark, quotes with a newline and a quote
        // inside, a column it does not know and a row without an address.
        let csv = "\u{feff}Nombre;Dirección;Puerto;Usuario;Carpeta;Coste;Notas\r\n\
                   \"Caja \"\"vieja\"\"\";caja.local;x;root;Casa\\Sótano;3;\"dos\r\nlíneas\"\r\n\
                   nas;nas.local;;;;;\r\n\
                   sin dirección;;;;;;\r\n\
                   nas;nas.local;;;;;\r\n";
        let b = parse(csv.as_bytes()).unwrap();
        assert_eq!(b.hosts.len(), 2, "the same row twice is one host");
        let caja = &b.hosts[0];
        assert_eq!(caja.label, "Caja \"vieja\"");
        assert_eq!(caja.group.as_deref(), Some("Casa/Sótano"));
        assert_eq!(caja.notes.as_deref(), Some("dos\nlíneas"));
        assert_eq!(caja.settings.port, None);
        assert_eq!(b.hosts[1].settings.user, None);
        let bad: Vec<_> = b
            .warnings
            .iter()
            .map(|w| (w.subject.as_deref(), &w.kind))
            .collect();
        assert_eq!(
            bad,
            [
                (
                    Some("Caja \"vieja\""),
                    &WarningKind::BadValue {
                        field: "port".into(),
                        value: "x".into()
                    }
                ),
                (
                    Some("sin dirección"),
                    &WarningKind::BadValue {
                        field: "hostname".into(),
                        value: String::new()
                    }
                ),
            ]
        );
    }

    #[test]
    fn keys_by_path_or_inside_the_cell() {
        let csv = "host\tkey\n\
                   a.example.com\t~/.ssh/id_ed25519\n\
                   b.example.com\t\"-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----\"\n";
        let b = parse(csv.as_bytes()).unwrap();
        assert_eq!(b.hosts[0].label, "a.example.com", "no name: the address");
        assert_eq!(b.hosts[0].keys, [KeyRef::Path("~/.ssh/id_ed25519".into())]);
        assert_eq!(b.hosts[1].keys, [KeyRef::Stored("row2".into())]);
        assert!(
            b.keys[0]
                .private_key
                .ends_with("-----END OPENSSH PRIVATE KEY-----")
        );
    }

    #[test]
    fn other_text_is_not_a_csv_of_hosts() {
        assert!(!sniff("name,price\nbread,1\n"));
        assert!(!sniff("hello"));
        assert!(parse(b"host,user\n").is_err());
    }
}
