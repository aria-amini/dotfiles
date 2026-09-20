use usage::{Args, Cli, Run, Subcommands};

use crate::repo;

/// Review image changes between two versions, in the terminal
#[derive(Cli)]
#[usage(bin = "idiff", version = "0.1.0", completion)]
pub(crate) struct Idiff {
    /// Revision to review (defaults to the working copy @)
    #[usage(short = 'r', long)]
    pub(crate) rev: Option<String>,
    /// Terminal image protocol (kitty, iterm2, sixel, ansi)
    #[usage(long)]
    pub(crate) renderer: Option<String>,
    /// Sixel palette depth in bits (1-8, default 8)
    #[usage(long, default = "8")]
    pub(crate) depth: u32,
    #[usage(subcommand)]
    pub(crate) command: Option<Commands>,
}

#[derive(Subcommands)]
pub(crate) enum Commands {
    /// Print a shell completion script
    Completions(Completions),
}

impl Idiff {
    pub(crate) fn dispatch(self) {
        match self.command {
            Some(Commands::Completions(c)) => c.run(),
            None => self.run_review(),
        }
    }

    fn run_review(self) {
        if !(1..=8).contains(&self.depth) {
            eprintln!("Error: --depth requires an integer in 1..=8");
            std::process::exit(1);
        }
        let cwd = match std::env::current_dir() {
            Ok(d) => d,
            Err(e) => {
                eprintln!("Error: cannot determine working directory: {e}");
                std::process::exit(1);
            }
        };
        let root = match repo::find_workspace_root(&cwd) {
            Some(r) => r,
            None => {
                eprintln!("Error: not inside a jj workspace (no .jj directory found)");
                std::process::exit(1);
            }
        };
        let rev = self.rev.unwrap_or_else(|| "@".to_string());
        let tmp = match tempfile::tempdir() {
            Ok(t) => t,
            Err(e) => {
                eprintln!("Error: cannot create temp directory: {e}");
                std::process::exit(1);
            }
        };
        let entries = match repo::changed_images(&root, &rev, &tmp) {
            Ok(e) => e,
            Err(e) => {
                eprintln!("Error: {e}");
                std::process::exit(1);
            }
        };
        if entries.is_empty() {
            println!("no image changes in {rev}");
            return;
        }

        let pairs = entries
            .into_iter()
            .map(|e| crate::Pair {
                label: e.path,
                status: Some(e.status),
                before: e.before,
                after: e.after,
            })
            .collect::<Vec<_>>();
        // TempDir stays alive for the whole session; sides live inside it.
        if let Err(e) = crate::run_review(&pairs, 0, self.renderer.as_deref(), self.depth) {
            eprintln!("Error: {e}");
            std::mem::forget(tmp);
            std::process::exit(1);
        }
    }
}

/// Print a shell completion script
#[derive(Args)]
pub(crate) struct Completions {
    /// Shell to generate the script for
    #[usage(choices("bash", "zsh", "fish"))]
    pub(crate) shell: String,
}

impl Run for Completions {
    type Output = ();
    fn run(self) {
        let shell = match self.shell.as_str() {
            "bash" => usage::complete::Shell::Bash,
            "zsh" => usage::complete::Shell::Zsh,
            _ => usage::complete::Shell::Fish,
        };
        print!("{}", Idiff::completion_script(shell));
    }
}
