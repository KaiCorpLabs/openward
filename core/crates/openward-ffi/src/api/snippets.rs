//! Snippets as Dart sees them, and the templates they are made of.

use std::collections::HashMap;

use flutter_rust_bridge::frb;
use openward_app::snippets::{BUILTINS, asked, render, variables};
use openward_app::vault::proto::{Data, Snippet};

use super::app::OpenWard;
use super::vault::VaultError;

/// A value for a variable: a default, or what the user typed.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnippetValue {
    pub name: String,
    pub value: String,
}

#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnippetSpec {
    pub label: String,
    /// One or more lines, sent as if typed.
    pub script: String,
    #[frb(default = "const []")]
    pub defaults: Vec<SnippetValue>,
    /// Leave it typed, without pressing Enter.
    #[frb(default = "false")]
    pub type_only: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnippetView {
    pub id: String,
    pub rev: u64,
    pub spec: SnippetSpec,
    pub variables: SnippetVariables,
}

/// What a script asks for, and which session values it uses.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SnippetVariables {
    pub asked: Vec<String>,
    pub builtins: Vec<String>,
}

fn variables_of(script: &str) -> SnippetVariables {
    SnippetVariables {
        asked: asked(script),
        builtins: variables(script)
            .into_iter()
            .filter(|v| BUILTINS.contains(&v.as_str()))
            .collect(),
    }
}

fn spec_of(s: &Snippet) -> SnippetSpec {
    SnippetSpec {
        label: s.label.clone(),
        script: s.script.clone(),
        defaults: s
            .defaults
            .iter()
            .map(|(name, value)| SnippetValue {
                name: name.clone(),
                value: value.clone(),
            })
            .collect(),
        type_only: s.type_only,
    }
}

/// Writes `spec` over `s`, keeping what OpenWard does not know.
fn apply(spec: &SnippetSpec, s: &mut Snippet) {
    s.label = spec.label.trim().to_owned();
    s.script = spec.script.trim_end_matches(['\n', '\r', ' ']).to_owned();
    s.defaults = spec
        .defaults
        .iter()
        .filter(|d| !d.value.is_empty())
        .map(|d| (d.name.clone(), d.value.clone()))
        .collect();
    s.type_only = spec.type_only;
}

impl OpenWard {
    /// Every snippet, by name.
    #[frb(sync)]
    pub fn snippets(&self) -> Vec<SnippetView> {
        let vault = self.app.vault();
        vault
            .snippets()
            .into_iter()
            .map(|(sid, s)| SnippetView {
                id: sid.to_string(),
                rev: vault.get(sid).map_or(0, |i| i.rev),
                spec: spec_of(s),
                variables: variables_of(&s.script),
            })
            .collect()
    }

    pub fn create_snippet(&self, spec: SnippetSpec) -> Result<String, VaultError> {
        let mut s = Snippet::default();
        apply(&spec, &mut s);
        Ok(self.app.vault().create(Data::Snippet(s))?.to_string())
    }

    /// Returns the new revision. Fails if it changed since `rev`.
    pub fn update_snippet(
        &self,
        id: String,
        rev: u64,
        spec: SnippetSpec,
    ) -> Result<u64, VaultError> {
        let sid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let mut s = vault.snippet(sid)?.clone();
        apply(&spec, &mut s);
        Ok(vault.update(sid, rev, Data::Snippet(s))?)
    }
}

/// What `script` asks for, as an editor shows it while typing.
#[frb(sync)]
pub fn snippet_variables(script: String) -> SnippetVariables {
    variables_of(&script)
}

/// `script` with its variables filled in; one without a value stays.
#[frb(sync)]
pub fn render_snippet(script: String, values: Vec<SnippetValue>) -> String {
    let values: HashMap<String, String> = values.into_iter().map(|v| (v.name, v.value)).collect();
    render(&script, &values)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_snippet_round_trips_through_its_spec() {
        let spec = SnippetSpec {
            label: "Logs".into(),
            script: "journalctl -u {{servicio}} -n {{líneas}} # {{host}}".into(),
            defaults: vec![SnippetValue {
                name: "líneas".into(),
                value: "20".into(),
            }],
            type_only: true,
        };
        let mut s = Snippet::default();
        apply(&spec, &mut s);
        assert_eq!(spec_of(&s), spec);
        let vars = variables_of(&s.script);
        assert_eq!(vars.asked, ["servicio", "líneas"]);
        assert_eq!(vars.builtins, ["host"]);
    }
}
