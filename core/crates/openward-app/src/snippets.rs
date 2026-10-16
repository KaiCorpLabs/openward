//! Snippet commands as templates: `{{name}}` is asked for when the snippet
//! runs, and a few names are filled in from each terminal's session.
//!
//! A name starts with a letter or `_` and goes on with letters, digits, `_`
//! and `-`, so Go templates (`{{.Name}}`, `{{range .items}}`) stay as they
//! are; `\{{` writes `{{` without starting a variable.

use std::collections::HashMap;

/// Names that come from the session, in each pane: the host's name, its
/// address, the user and the port.
pub const BUILTINS: &[&str] = &["host", "address", "user", "port"];

/// A piece of a script: text as written, or a variable.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Part<'a> {
    Text(&'a str),
    Var(&'a str),
}

fn is_name(s: &str) -> bool {
    let mut chars = s.chars();
    chars.next().is_some_and(|c| c.is_alphabetic() || c == '_')
        && chars.all(|c| c.is_alphanumeric() || c == '_' || c == '-')
}

/// `script` cut into text and variables. An escaped `\{{` comes out as
/// the text `{{`.
pub fn parts(script: &str) -> Vec<Part<'_>> {
    let mut out = Vec::new();
    let mut rest = script;
    while let Some(at) = rest.find("{{") {
        if at > 0 && rest[..at].ends_with('\\') {
            out.push(Part::Text(&rest[..at - 1]));
            out.push(Part::Text("{{"));
            rest = &rest[at + 2..];
            continue;
        }
        let Some(len) = rest[at + 2..].find("}}") else {
            break;
        };
        let inner = &rest[at + 2..at + 2 + len];
        let name = inner.trim();
        if is_name(name) {
            if at > 0 {
                out.push(Part::Text(&rest[..at]));
            }
            out.push(Part::Var(name));
            rest = &rest[at + 2 + len + 2..];
        } else {
            out.push(Part::Text(&rest[..at + 2]));
            rest = &rest[at + 2..];
        }
    }
    if !rest.is_empty() {
        out.push(Part::Text(rest));
    }
    out
}

/// Every variable of `script`, in order of first appearance, each once.
pub fn variables(script: &str) -> Vec<String> {
    let mut seen = Vec::<String>::new();
    for p in parts(script) {
        if let Part::Var(name) = p
            && !seen.iter().any(|s| s == name)
        {
            seen.push(name.to_owned());
        }
    }
    seen
}

/// The variables to ask for: those not filled in from the session.
pub fn asked(script: &str) -> Vec<String> {
    variables(script)
        .into_iter()
        .filter(|v| !BUILTINS.contains(&v.as_str()))
        .collect()
}

/// `script` with each variable replaced by its value. One without a value
/// stays as written.
pub fn render(script: &str, values: &HashMap<String, String>) -> String {
    let mut out = String::with_capacity(script.len());
    for p in parts(script) {
        match p {
            Part::Text(t) => out.push_str(t),
            Part::Var(name) => match values.get(name) {
                Some(v) => out.push_str(v),
                None => {
                    out.push_str("{{");
                    out.push_str(name);
                    out.push_str("}}");
                }
            },
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn values(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    #[test]
    fn variables_in_order_once_and_the_asked_ones() {
        let script = "journalctl -u {{servicio}} -n {{ líneas }} # {{servicio}} on {{host}}";
        assert_eq!(variables(script), ["servicio", "líneas", "host"]);
        assert_eq!(asked(script), ["servicio", "líneas"]);
        assert_eq!(
            render(
                script,
                &values(&[("servicio", "nginx"), ("líneas", "50"), ("host", "web-1")])
            ),
            "journalctl -u nginx -n 50 # nginx on web-1"
        );
    }

    #[test]
    fn go_templates_and_escapes_stay_as_written() {
        let script = r#"docker ps --format '{{.Names}}' {{ range .x }} \{{name}} {{name}}"#;
        assert_eq!(variables(script), ["name"]);
        assert_eq!(
            render(script, &values(&[("name", "web")])),
            "docker ps --format '{{.Names}}' {{ range .x }} {{name}} web"
        );
        // Unclosed, and empty.
        assert_eq!(variables("echo {{a"), Vec::<String>::new());
        assert_eq!(render("echo {{}} {{a", &values(&[])), "echo {{}} {{a");
        // Missing values stay.
        assert_eq!(render("ls {{dir}}", &values(&[])), "ls {{dir}}");
    }
}
