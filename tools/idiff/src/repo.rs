use std::path::{Path, PathBuf};
use std::process::Command;

use tempfile::TempDir;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Status {
    Added,
    Modified,
    Deleted,
}

impl Status {
    pub(crate) fn label(self) -> &'static str {
        match self {
            Self::Added => "added",
            Self::Modified => "modified",
            Self::Deleted => "deleted",
        }
    }

    fn from_marker(marker: &str) -> Option<Self> {
        match marker {
            "A" => Some(Self::Added),
            "M" => Some(Self::Modified),
            "D" => Some(Self::Deleted),
            _ => None,
        }
    }
}

pub(crate) struct Entry {
    /// Repo-relative path, used as the display label and tv entry.
    pub(crate) path: String,
    pub(crate) status: Status,
    /// Materialized parent-side content; None for added files.
    pub(crate) before: Option<PathBuf>,
    /// Materialized commit-side content; None for deleted files.
    pub(crate) after: Option<PathBuf>,
}

const IMAGE_EXTS: &[&str] = &[
    "png", "jpg", "jpeg", "jpe", "webp", "gif", "bmp", "tif", "tiff", "avif", "ico", "svg", "svgz",
    "qoi", "tga", "dds", "ff", "pbm", "pgm", "ppm", "pam", "hdr", "exr",
];

pub(crate) fn is_image_path(path: &str) -> bool {
    Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .is_some_and(|e| IMAGE_EXTS.contains(&e.as_str()))
}

/// Walk up from `start` looking for a `.jj` workspace marker.
pub(crate) fn find_workspace_root(start: &Path) -> Option<PathBuf> {
    let mut dir = Some(start);
    while let Some(d) = dir {
        if d.join(".jj").is_dir() {
            return Some(d.to_path_buf());
        }
        dir = d.parent();
    }
    None
}

fn parse_summary(summary: &str) -> Vec<(Status, String)> {
    summary
        .lines()
        .filter_map(|line| {
            let (marker, path) = line.split_once(' ')?;
            let status = Status::from_marker(marker.trim())?;
            Some((status, path.to_string()))
        })
        .collect()
}

/// List image files changed in `rev`, with their sides materialized into
/// `tmp`. Renames (which jj reports as `R{old} => {new}`) are skipped, as
/// are files whose sides fail to materialize.
pub(crate) fn changed_images(root: &Path, rev: &str, tmp: &TempDir) -> Result<Vec<Entry>, String> {
    let summary = jj(root, ["diff", "-r", rev, "--summary"])?;
    let summary = String::from_utf8_lossy(&summary);
    let mut entries = Vec::new();
    for (status, path) in parse_summary(&summary) {
        if !is_image_path(&path) {
            continue;
        }
        let before = match status {
            Status::Added => None,
            _ => materialize(
                root,
                &format!("{rev}-"),
                &path,
                tmp,
                entries.len(),
                "before",
            ),
        };
        let after = match status {
            Status::Deleted => None,
            _ => materialize(root, rev, &path, tmp, entries.len(), "after"),
        };
        if before.is_none() && after.is_none() {
            continue;
        }
        entries.push(Entry {
            path,
            status,
            before,
            after,
        });
    }
    Ok(entries)
}

/// Write one side of a file pair into `tmp` via `jj file show`.
///
/// The path is wrapped in literal quotes: jj parses the argument as a
/// fileset, where characters like `$` would otherwise start a function call.
fn materialize(
    root: &Path,
    rev: &str,
    path: &str,
    tmp: &TempDir,
    index: usize,
    side: &str,
) -> Option<PathBuf> {
    let ext = Path::new(path)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("img");
    let out = tmp.path().join(format!("{index:04}-{side}.{ext}"));
    let bytes = jj(
        root,
        ["file", "show", "-r", rev, "--", &format!("\"{path}\"")],
    )
    .ok()?;
    if bytes.is_empty() {
        return None;
    }
    std::fs::write(&out, bytes).ok()?;
    Some(out)
}

fn jj(root: &Path, args: impl IntoIterator<Item = impl AsRef<str>>) -> Result<Vec<u8>, String> {
    let args: Vec<String> = args.into_iter().map(|a| a.as_ref().to_string()).collect();
    let output = Command::new("jj")
        .args(&args)
        .current_dir(root)
        .output()
        .map_err(|e| format!("failed to run jj {}: {e}", args.join(" ")))?;
    if !output.status.success() {
        return Err(format!(
            "jj {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(output.stdout)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn summary_parses_added_modified_deleted() {
        let summary = "A photos/new.png\nM photos/old.jpg\nD gone.svg\n";
        let parsed = parse_summary(summary);
        assert_eq!(parsed.len(), 3);
        assert_eq!(parsed[0].0, Status::Added);
        assert_eq!(parsed[0].1, "photos/new.png");
        assert_eq!(parsed[1].0, Status::Modified);
        assert_eq!(parsed[2].0, Status::Deleted);
    }

    #[test]
    fn summary_skips_renames_and_unknown_markers() {
        let summary = "R{old.png => new.png}\nC weird.txt\nM a.bmp\n";
        let parsed = parse_summary(summary);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].1, "a.bmp");
    }

    #[test]
    fn image_detection_covers_common_and_svg_extensions() {
        assert!(is_image_path("x/y.PNG"));
        assert!(is_image_path("a.svgz"));
        assert!(!is_image_path("a.rs"));
        assert!(!is_image_path("noext"));
    }
}
