//! Writes the shared synthetic workloads (crate `s1-corpus`) to files.

use std::fs;
use std::path::Path;

use s1_corpus::Workload;

use crate::Opts;

pub fn generate(dir: &Path, o: &Opts) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
    let target = o.mb * 1024 * 1024;
    for workload in Workload::ALL {
        let data = workload.generate(target, usize::from(o.cols), usize::from(o.rows));
        let path = dir.join(format!("{}.txt", workload.name()));
        fs::write(&path, data.as_bytes()).map_err(|e| format!("{}: {e}", path.display()))?;
        println!(
            "{:>8.1} MiB  {}",
            data.len() as f64 / 1_048_576.0,
            path.display()
        );
    }
    Ok(())
}
