//! Workspaces as Dart sees them: tabs and panes saved to open again. A
//! tab's panes travel as a list in preorder (a split, then its first part,
//! then its second), so Dart gets no recursive type.

use flutter_rust_bridge::frb;
use openward_app::vault::proto::{
    Data, Extra, PaneLayout, PaneSplit, Target, Workspace, WorkspaceTab,
};

use super::app::OpenWard;

/// A saved host (`host_id`), an address, or (none of them) a shell here.
#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct WorkspaceTarget {
    pub host_id: Option<String>,
    pub address: Option<String>,
    pub user: Option<String>,
    pub port: Option<u16>,
}

#[frb(non_opaque)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WorkspaceSplit {
    /// One above the other; otherwise side by side.
    pub vertical: bool,
    pub ratio: f64,
}

/// A split (followed by its two parts), a pane with a target, or a pane
/// that asks what to open.
#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq)]
pub struct WorkspacePane {
    pub split: Option<WorkspaceSplit>,
    pub target: Option<WorkspaceTarget>,
    /// Had the keyboard.
    pub active: bool,
}

/// Terminals (`panes`, in preorder) or a file browser (`sftp`).
#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq)]
pub struct WorkspaceTabSpec {
    pub title: Option<String>,
    pub panes: Vec<WorkspacePane>,
    pub sftp: Option<WorkspaceTarget>,
}

#[frb(non_opaque)]
#[derive(Clone, Debug, PartialEq)]
pub struct WorkspaceSpec {
    pub name: String,
    pub tabs: Vec<WorkspaceTabSpec>,
    /// The tab in front, by index.
    pub active: u32,
}

#[derive(Clone, Debug, PartialEq)]
pub struct WorkspaceView {
    pub id: String,
    pub rev: u64,
    pub spec: WorkspaceSpec,
    /// Panes and tabs, to say how much it opens.
    pub sessions: u32,
}

fn target_view(t: &Target) -> WorkspaceTarget {
    WorkspaceTarget {
        host_id: t.host.map(|h| h.to_string()),
        address: t.address.clone(),
        user: t.user.clone(),
        port: t.port,
    }
}

fn target_of(t: &WorkspaceTarget) -> anyhow::Result<Target> {
    let text = |s: &Option<String>| {
        s.as_ref()
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty())
    };
    Ok(Target {
        host: super::vault::opt_id(&t.host_id)?,
        address: text(&t.address),
        user: text(&t.user),
        port: t.port.filter(|p| *p > 0),
        extra: Extra::new(),
    })
}

fn flatten(n: &PaneLayout, out: &mut Vec<WorkspacePane>) {
    out.push(WorkspacePane {
        split: n.split.as_ref().map(|s| WorkspaceSplit {
            vertical: s.vertical,
            ratio: s.ratio,
        }),
        target: if n.split.is_some() {
            None
        } else {
            n.target.as_ref().map(target_view)
        },
        active: n.active,
    });
    if let Some(s) = &n.split {
        flatten(&s.first, out);
        flatten(&s.second, out);
    }
}

/// The tree back from its preorder; a list cut short ends in panes that
/// ask what to open.
fn unflatten(
    panes: &mut std::slice::Iter<'_, WorkspacePane>,
    depth: usize,
) -> anyhow::Result<PaneLayout> {
    let Some(p) = panes.next() else {
        return Ok(PaneLayout::default());
    };
    let mut node = PaneLayout {
        active: p.active,
        ..PaneLayout::default()
    };
    match &p.split {
        // Deep enough for any window; more is a list gone wrong.
        Some(s) if depth < 32 => {
            node.split = Some(Box::new(PaneSplit {
                vertical: s.vertical,
                ratio: if s.ratio.is_finite() {
                    s.ratio.clamp(0.05, 0.95)
                } else {
                    0.5
                },
                first: unflatten(panes, depth + 1)?,
                second: unflatten(panes, depth + 1)?,
                extra: Extra::new(),
            }));
        }
        Some(_) => anyhow::bail!("panes nested too deep"),
        None => node.target = p.target.as_ref().map(target_of).transpose()?,
    }
    Ok(node)
}

fn spec_of(w: &Workspace) -> WorkspaceSpec {
    WorkspaceSpec {
        name: w.name.clone(),
        tabs: w
            .tabs
            .iter()
            .map(|t| {
                let mut panes = Vec::new();
                if let Some(p) = &t.panes {
                    flatten(p, &mut panes);
                }
                WorkspaceTabSpec {
                    title: t.title.clone(),
                    panes,
                    sftp: t.sftp.as_ref().map(target_view),
                }
            })
            .collect(),
        active: w.active,
    }
}

/// Writes `spec` over `w`, keeping what OpenWard does not know of the
/// workspace itself (its tabs are new).
fn apply(spec: &WorkspaceSpec, w: &mut Workspace) -> anyhow::Result<()> {
    w.name = spec.name.trim().to_owned();
    w.tabs = spec
        .tabs
        .iter()
        .map(|t| {
            Ok(WorkspaceTab {
                title: t.title.clone().filter(|s| !s.trim().is_empty()),
                panes: if t.panes.is_empty() {
                    None
                } else {
                    Some(unflatten(&mut t.panes.iter(), 0)?)
                },
                sftp: t.sftp.as_ref().map(target_of).transpose()?,
                extra: Extra::new(),
            })
        })
        .collect::<anyhow::Result<_>>()?;
    w.active = spec.active.min(w.tabs.len().saturating_sub(1) as u32);
    Ok(())
}

fn sessions(w: &Workspace) -> u32 {
    fn count(n: &PaneLayout) -> u32 {
        match &n.split {
            Some(s) => count(&s.first) + count(&s.second),
            None => 1,
        }
    }
    w.tabs
        .iter()
        .map(|t| t.panes.as_ref().map_or(1, count))
        .sum()
}

impl OpenWard {
    /// Every workspace, by name.
    #[frb(sync)]
    pub fn workspaces(&self) -> Vec<WorkspaceView> {
        let vault = self.app.vault();
        vault
            .workspaces()
            .into_iter()
            .map(|(wid, w)| WorkspaceView {
                id: wid.to_string(),
                rev: vault.get(wid).map_or(0, |i| i.rev),
                spec: spec_of(w),
                sessions: sessions(w),
            })
            .collect()
    }

    pub fn create_workspace(&self, spec: WorkspaceSpec) -> anyhow::Result<String> {
        let mut w = Workspace::default();
        apply(&spec, &mut w)?;
        Ok(self.app.vault().create(Data::Workspace(w))?.to_string())
    }

    /// Returns the new revision. Fails if it changed since `rev`.
    pub fn update_workspace(
        &self,
        id: String,
        rev: u64,
        spec: WorkspaceSpec,
    ) -> anyhow::Result<u64> {
        let wid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let mut w = vault.workspace(wid)?.clone();
        apply(&spec, &mut w)?;
        Ok(vault.update(wid, rev, Data::Workspace(w))?)
    }

    /// Renames it, leaving its tabs as they are.
    pub fn rename_workspace(&self, id: String, rev: u64, name: String) -> anyhow::Result<u64> {
        let wid = super::vault::id(&id)?;
        let mut vault = self.app.vault();
        let mut w = vault.workspace(wid)?.clone();
        w.name = name.trim().to_owned();
        Ok(vault.update(wid, rev, Data::Workspace(w))?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nowhere() -> WorkspaceTarget {
        WorkspaceTarget {
            host_id: None,
            address: None,
            user: None,
            port: None,
        }
    }

    fn pane(host: Option<&str>) -> WorkspacePane {
        WorkspacePane {
            split: None,
            target: Some(WorkspaceTarget {
                host_id: host.map(str::to_owned),
                ..nowhere()
            }),
            active: false,
        }
    }

    #[test]
    fn panes_go_through_their_preorder_and_back() {
        let host = openward_app::vault::proto::ItemId::new().to_string();
        let split = |vertical| WorkspacePane {
            split: Some(WorkspaceSplit {
                vertical,
                ratio: 0.3,
            }),
            target: None,
            active: false,
        };
        // [local | [host / empty]]
        let spec = WorkspaceSpec {
            name: " Producción ".into(),
            tabs: vec![
                WorkspaceTabSpec {
                    title: Some("web".into()),
                    panes: vec![
                        split(false),
                        pane(None),
                        split(true),
                        WorkspacePane {
                            active: true,
                            ..pane(Some(&host))
                        },
                        WorkspacePane {
                            split: None,
                            target: None,
                            active: false,
                        },
                    ],
                    sftp: None,
                },
                WorkspaceTabSpec {
                    title: None,
                    panes: vec![],
                    sftp: Some(WorkspaceTarget {
                        address: Some("10.0.0.5".into()),
                        user: Some("deploy".into()),
                        port: Some(2222),
                        ..nowhere()
                    }),
                },
            ],
            active: 7,
        };
        let mut w = Workspace::default();
        apply(&spec, &mut w).unwrap();
        assert_eq!(w.name, "Producción");
        assert_eq!(w.active, 1, "an index past the end is the last tab");
        assert_eq!(sessions(&w), 4);
        let back = spec_of(&w);
        assert_eq!(back.tabs[0].panes, spec.tabs[0].panes);
        assert_eq!(back.tabs[1], spec.tabs[1]);
    }

    #[test]
    fn a_list_cut_short_ends_in_empty_panes() {
        let spec = WorkspaceSpec {
            name: "x".into(),
            tabs: vec![WorkspaceTabSpec {
                title: None,
                panes: vec![WorkspacePane {
                    split: Some(WorkspaceSplit {
                        vertical: false,
                        ratio: f64::NAN,
                    }),
                    target: None,
                    active: false,
                }],
                sftp: None,
            }],
            active: 0,
        };
        let mut w = Workspace::default();
        apply(&spec, &mut w).unwrap();
        let split = w.tabs[0].panes.as_ref().unwrap().split.as_ref().unwrap();
        assert_eq!(split.ratio, 0.5);
        assert_eq!(split.first, PaneLayout::default());
        assert_eq!(sessions(&w), 2);
    }
}
