// link-handler — zellij's built-in `link` plugin (default-plugins/link at
// v0.44.3, MIT), forked to change what a click DOES. Upstream opens files in
// $EDITOR (floating pane) and directories in the filepicker; this fork opens
// both in a new tab cwd'd at the path's directory, auto-named after its git
// repo — the same behavior as newtab.sh. Everything else (path regex, hover
// underline/italic, cwd tracking, dir-entry highlights, ~/$VAR expansion) is
// upstream, kept verbatim so the fork stays diffable against new zellij
// releases.
//
// Deltas from upstream, in full:
//   - request_permission + Event::PermissionRequestResult handling: built-in
//     plugins are implicitly trusted, user plugins must ask. Loaded as a
//     background plugin there is no pane to show the grant prompt in, so
//     hearth pre-seeds zellij's permission cache (see modules/hearth).
//   - handle_highlight_clicked: new-tab-with-cwd instead of $EDITOR/filepicker.
//   - URL_REGEX + open_target: http(s) URLs are highlighted too and open in
//     the default browser via `open` (hence RunCommands). open_target is the
//     dispatch point for any future per-kind click behavior.
//   - tooltip says where the click goes.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use zellij_tile::prelude::*;

const FILE_PATH_REGEX: &str = r#"(?:^|\s)((?:(?:\./|\.\./|/)[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+|~/[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+)(?::\d+(?::\d+)?)?)(?::|\s|$)"#;

// Ends at whitespace or a quote/angle delimiter; trailing sentence
// punctuation the character class can't exclude (a URL inside parens or at
// the end of a sentence) is trimmed on click by parse_url.
const URL_REGEX: &str = r#"\b(https?://[^\s"'<>]+)"#;

const CWD_CONTEXT_KEY: &str = "cwd";

#[derive(Default)]
struct State {
    known_terminal_panes: HashSet<PaneId>,
    /// Tracks the current CWD for each terminal pane.
    pane_cwds: HashMap<PaneId, PathBuf>,
    /// Tracks the directory entry names highlighted for each pane,
    /// so they can be removed when the CWD changes.
    pane_dir_entries: HashMap<PaneId, Vec<String>>,
    /// Session environment variables, fetched once permissions are granted.
    /// Used for `~` and `$VAR` expansion in clicked paths.
    env_vars: BTreeMap<String, String>,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        // Everything below PermissionRequestResult is gated on the grant:
        // host-folder access, pane cwds and tab-opening are all
        // permissioned for non-builtin plugins.
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::FullHdAccess,
            PermissionType::RunCommands,
            PermissionType::ReadSessionEnvironmentVariables,
        ]);
        subscribe(&[
            EventType::PermissionRequestResult,
            EventType::PaneUpdate,
            EventType::HighlightClicked,
            EventType::CwdChanged,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                // Set host folder to "/" so that /host maps to the real
                // filesystem root, allowing std::fs operations on
                // /host/<absolute_path>.
                change_host_folder(PathBuf::from("/"));
                self.env_vars = get_session_environment_variables();
            },
            Event::PaneUpdate(pane_manifest) => {
                self.handle_pane_update(pane_manifest);
            },
            Event::HighlightClicked {
                pane_id: _,
                pattern: _,
                matched_string,
                context,
            } => {
                self.handle_highlight_clicked(matched_string, context);
            },
            Event::CwdChanged(pane_id, new_cwd, _focused_client_ids) => {
                self.handle_cwd_changed(pane_id, new_cwd);
            },
            _ => {},
        }
        false // never render — background-only plugin
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // Background-only plugin. Never rendered. Intentionally empty.
    }
}

impl State {
    fn handle_pane_update(&mut self, pane_manifest: PaneManifest) {
        let mut current_panes: HashSet<PaneId> = HashSet::new();

        for (_tab_index, panes) in &pane_manifest.panes {
            for pane_info in panes {
                if !pane_info.is_plugin {
                    let pane_id = PaneId::Terminal(pane_info.id);
                    current_panes.insert(pane_id);
                }
            }
        }

        // Set highlights on newly appeared terminal panes
        for &pane_id in &current_panes {
            if !self.known_terminal_panes.contains(&pane_id) {
                // Fetch the pane's current CWD and scan its directory
                if let Ok(cwd) = get_pane_cwd(pane_id) {
                    self.scan_and_store_dir_entries(pane_id, &cwd);
                    self.pane_cwds.insert(pane_id, cwd);
                }
                self.set_all_highlights_for_pane(pane_id);
            }
        }

        // Clean up tracking state for panes that no longer exist
        for &pane_id in &self.known_terminal_panes {
            if !current_panes.contains(&pane_id) {
                self.pane_cwds.remove(&pane_id);
                self.pane_dir_entries.remove(&pane_id);
            }
        }

        self.known_terminal_panes = current_panes;
    }

    fn handle_cwd_changed(&mut self, pane_id: PaneId, new_cwd: PathBuf) {
        let old_cwd = self.pane_cwds.get(&pane_id);
        if old_cwd == Some(&new_cwd) {
            return;
        }

        self.pane_cwds.insert(pane_id, new_cwd.clone());
        self.scan_and_store_dir_entries(pane_id, &new_cwd);

        // clear_pane_highlights removes all highlights, then re-set everything
        // (file-path regex + directory entry patterns)
        clear_pane_highlights(pane_id);
        self.set_all_highlights_for_pane(pane_id);
    }

    /// Dispatch a click by what was matched. Future per-kind behaviors
    /// (GitHub URLs, image files, …) branch from here.
    fn handle_highlight_clicked(&self, matched_string: String, context: BTreeMap<String, String>) {
        if let Some(url) = parse_url(matched_string.trim()) {
            run_command(&["/usr/bin/open", url], BTreeMap::new());
            return;
        }
        self.open_path_in_new_tab(matched_string, context);
    }

    fn open_path_in_new_tab(&self, matched_string: String, context: BTreeMap<String, String>) {
        let (path_str, _line_number) = parse_path_and_line(&matched_string);
        let path_str = path_str.trim();
        let expanded = expand_path(path_str, &self.env_vars);
        let path_str = expanded.as_str();

        // Resolve to a fully qualified path: if relative, join with the
        // pane CWD stored in the highlight context.
        let absolute_path = if path_str.starts_with('/') {
            PathBuf::from(path_str)
        } else if let Some(cwd) = context.get(CWD_CONTEXT_KEY) {
            PathBuf::from(cwd).join(path_str)
        } else {
            PathBuf::from(path_str)
        };

        // Validate the path exists via the /host/ filesystem mapping
        // established after the permission grant. This guards against regex
        // false positives that match non-path text in terminal output.
        let metadata = match std::fs::metadata(host_path(&absolute_path)) {
            Ok(m) => m,
            Err(_) => return, // path does not exist — silently ignore
        };

        // A file opens at its parent directory; a directory opens at itself.
        let dir = if metadata.is_dir() {
            absolute_path
        } else {
            match absolute_path.parent() {
                Some(parent) => parent.to_path_buf(),
                None => return,
            }
        };

        let name = tab_name_for(&dir);
        match self.layout_with_cwd(&dir, &name) {
            Some(layout) => {
                new_tabs_with_layout(&layout);
            },
            None => {
                // Layout missing/reformatted: at least name the tab; cwd may
                // land in $HOME (`new-tab --cwd` is ignored under a
                // default_tab_template) — same fallback as newtab.sh.
                new_tab(Some(name.as_str()), Some(dir.to_string_lossy().as_ref()));
            },
        }
    }

    /// Clone the live layout file and inject cwd + name onto its content tab —
    /// the same trick as newtab.sh: `new-tab --cwd` is silently ignored when a
    /// default_tab_template is active (zellij 0.44), but a tab-level cwd in a
    /// layout IS honored, and reusing custom.kdl verbatim keeps the
    /// tab-bar/status-bar and the spiral/columns/grid swap layouts intact.
    fn layout_with_cwd(&self, dir: &Path, name: &str) -> Option<String> {
        let home = self.env_vars.get("HOME")?;
        let layout_src = Path::new(home).join(".config/zellij/layouts/custom.kdl");
        let src = std::fs::read_to_string(host_path(&layout_src)).ok()?;

        // KDL-escape (backslash then double-quote), mirroring newtab.sh.
        let cwd_escaped = kdl_escape(&dir.to_string_lossy());
        let name_escaped = kdl_escape(name);

        let mut done = false;
        let out: Vec<String> = src
            .lines()
            .map(|line| {
                if !done && line == "    tab {" {
                    done = true;
                    format!("    tab cwd=\"{}\" name=\"{}\" {{", cwd_escaped, name_escaped)
                } else {
                    line.to_string()
                }
            })
            .collect();
        done.then(|| out.join("\n"))
    }

    /// (Re-)set all regex highlights for a pane: the general file-path regex
    /// plus any directory-entry patterns derived from the pane's CWD.
    fn set_all_highlights_for_pane(&self, pane_id: PaneId) {
        let mut highlights = Vec::new();

        // Build context map containing the pane CWD (echoed back on click)
        let context = self.cwd_context_for_pane(pane_id);

        // General file-path regex (always present)
        highlights.push(RegexHighlight {
            pattern: FILE_PATH_REGEX.to_owned(),
            style: HighlightStyle::None,
            layer: HighlightLayer::Hint,
            context: context.clone(),
            on_hover: true,
            bold: false,
            italic: true,
            underline: true,
            tooltip_text: Some("Open in new tab".to_string()),
        });

        // http(s) URLs (always present)
        highlights.push(RegexHighlight {
            pattern: URL_REGEX.to_owned(),
            style: HighlightStyle::None,
            layer: HighlightLayer::Hint,
            context: context.clone(),
            on_hover: true,
            bold: false,
            italic: true,
            underline: true,
            tooltip_text: Some("Open in browser".to_string()),
        });

        // Directory-entry patterns for the pane's current CWD
        if let Some(entries) = self.pane_dir_entries.get(&pane_id) {
            for entry_name in entries {
                let path_chars = r#"[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]"#;
                let pattern = format!(
                    "(?:^|\\s)({}(?:/{path_chars}+)?(?::\\d+(?::\\d+)?)?)(?::|\\s|$)",
                    regex_escape(entry_name),
                );
                highlights.push(RegexHighlight {
                    pattern,
                    style: HighlightStyle::None,
                    layer: HighlightLayer::Hint,
                    context: context.clone(),
                    on_hover: true,
                    bold: false,
                    italic: true,
                    underline: true,
                    tooltip_text: Some("Open in new tab".to_string()),
                });
            }
        }

        set_pane_regex_highlights(pane_id, highlights);
    }

    fn scan_and_store_dir_entries(&mut self, pane_id: PaneId, cwd: &Path) {
        let dir_entries = scan_directory(&host_path(cwd));
        self.pane_dir_entries.insert(pane_id, dir_entries);
    }

    fn cwd_context_for_pane(&self, pane_id: PaneId) -> BTreeMap<String, String> {
        let mut context = BTreeMap::new();
        if let Some(cwd) = self.pane_cwds.get(&pane_id) {
            context.insert(CWD_CONTEXT_KEY.to_owned(), cwd.display().to_string());
        }
        context
    }
}

/// Map a real absolute path onto the plugin's /host mount (host folder is "/").
fn host_path(path: &Path) -> PathBuf {
    Path::new("/host").join(path.strip_prefix("/").unwrap_or(path))
}

/// The tab name for a directory: its git-root's basename, or its own basename
/// outside a repo — the same naming as newtab.sh. `.git` is checked with
/// metadata (not is_dir) because linked worktrees and submodules have a
/// `.git` FILE.
fn tab_name_for(dir: &Path) -> String {
    let mut git_root = None;
    let mut current = Some(dir.to_path_buf());
    while let Some(candidate) = current {
        if std::fs::metadata(host_path(&candidate.join(".git"))).is_ok() {
            git_root = Some(candidate);
            break;
        }
        current = candidate.parent().map(Path::to_path_buf);
    }
    git_root
        .as_deref()
        .unwrap_or(dir)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "new".to_string())
}

/// Recognize an http(s) URL in a clicked highlight. URL_REGEX runs to the
/// next whitespace, so sentence punctuation and closing brackets around the
/// URL get matched too — trim them here.
fn parse_url(s: &str) -> Option<&str> {
    if !(s.starts_with("http://") || s.starts_with("https://")) {
        return None;
    }
    let mut trimmed = s;
    while !trimmed.is_empty() {
        let last_char = trimmed.chars().next_back()?;
        if ".,;:!?\"'".contains(last_char) {
            trimmed = &trimmed[..trimmed.len() - last_char.len_utf8()];
        } else if last_char == ')' {
            // Trim trailing ')' ONLY if parentheses are unbalanced
            if trimmed.contains('(') {
                let open_count = trimmed.chars().filter(|&c| c == '(').count();
                let close_count = trimmed.chars().filter(|&c| c == ')').count();
                if close_count > open_count {
                    trimmed = &trimmed[..trimmed.len() - 1];
                } else {
                    break;
                }
            } else {
                trimmed = &trimmed[..trimmed.len() - 1];
            }
        } else if last_char == ']' {
            if trimmed.contains('[') {
                let open_count = trimmed.chars().filter(|&c| c == '[').count();
                let close_count = trimmed.chars().filter(|&c| c == ']').count();
                if close_count > open_count {
                    trimmed = &trimmed[..trimmed.len() - 1];
                } else {
                    break;
                }
            } else {
                trimmed = &trimmed[..trimmed.len() - 1];
            }
        } else if last_char == '}' {
            if trimmed.contains('{') {
                let open_count = trimmed.chars().filter(|&c| c == '{').count();
                let close_count = trimmed.chars().filter(|&c| c == '}').count();
                if close_count > open_count {
                    trimmed = &trimmed[..trimmed.len() - 1];
                } else {
                    break;
                }
            } else {
                trimmed = &trimmed[..trimmed.len() - 1];
            }
        } else {
            break;
        }
    }
    Some(trimmed)
}

fn kdl_escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

/// Scan a directory for first-level file and folder names.
/// Returns an empty vec on any error.
/// Maximum number of directory entries to scan. Directories with more entries
/// than this are skipped entirely to avoid excessive regex pattern count.
const MAX_DIR_ENTRIES: usize = 500;

fn scan_directory(path: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    let read_dir = match std::fs::read_dir(path) {
        Ok(rd) => rd,
        Err(_) => return entries,
    };
    for entry in read_dir {
        if let Ok(entry) = entry {
            if let Some(name) = entry.file_name().to_str() {
                entries.push(name.to_owned());
                if entries.len() > MAX_DIR_ENTRIES {
                    return Vec::new();
                }
            }
        }
    }
    entries
}

/// Escape a string so it is treated as a literal in a regex pattern.
fn regex_escape(s: &str) -> String {
    let mut escaped = String::with_capacity(s.len() + 8);
    for c in s.chars() {
        match c {
            '\\' | '.' | '+' | '*' | '?' | '(' | ')' | '|' | '[' | ']' | '{' | '}' | '^' | '$' => {
                escaped.push('\\');
                escaped.push(c);
            },
            _ => escaped.push(c),
        }
    }
    escaped
}

/// Expand `~` and `$VAR` / `${VAR}` references in a path string.
///
/// - `~` at the start (followed by `/` or at end-of-string) is replaced with
///   the value of `HOME` from `env_vars`.
/// - `$VARNAME` and `${VARNAME}` anywhere in the string are replaced with the
///   corresponding value from `env_vars`.
/// - Unrecognized variables and a missing `HOME` are left as-is.
fn expand_path(path: &str, env_vars: &BTreeMap<String, String>) -> String {
    // Step 1: tilde expansion (only leading ~)
    let after_tilde = if path == "~" {
        match env_vars.get("HOME") {
            Some(home) => home.clone(),
            None => path.to_owned(),
        }
    } else if let Some(rest) = path.strip_prefix("~/") {
        match env_vars.get("HOME") {
            Some(home) => format!("{}/{}", home, rest),
            None => path.to_owned(),
        }
    } else {
        path.to_owned()
    };

    // Step 2: environment variable expansion ($VAR and ${VAR})
    let bytes = after_tilde.as_bytes();
    let len = bytes.len();
    let mut result = String::with_capacity(len);
    let mut i = 0;

    while i < len {
        if bytes[i] == b'$' && i + 1 < len {
            let (var_name, end_idx) = if bytes[i + 1] == b'{' {
                // ${VAR} form
                if let Some(close) = after_tilde[i + 2..].find('}') {
                    let name = &after_tilde[i + 2..i + 2 + close];
                    (name, i + 2 + close + 1)
                } else {
                    // No closing brace — not a valid variable reference
                    result.push('$');
                    i += 1;
                    continue;
                }
            } else {
                // $VAR form — variable name is [A-Za-z_][A-Za-z0-9_]*
                let start = i + 1;
                if start < len && (bytes[start].is_ascii_alphabetic() || bytes[start] == b'_') {
                    let mut end = start + 1;
                    while end < len && (bytes[end].is_ascii_alphanumeric() || bytes[end] == b'_') {
                        end += 1;
                    }
                    (&after_tilde[start..end], end)
                } else {
                    result.push('$');
                    i += 1;
                    continue;
                }
            };

            if let Some(value) = env_vars.get(var_name) {
                result.push_str(value);
            } else {
                // Unknown variable — preserve the original text
                result.push_str(&after_tilde[i..end_idx]);
            }
            i = end_idx;
        } else {
            result.push(bytes[i] as char);
            i += 1;
        }
    }

    result
}

fn parse_path_and_line(matched_string: &str) -> (&str, Option<usize>) {
    let mut end = matched_string.len();
    let mut numeric_segments: Vec<(usize, &str)> = Vec::new();

    loop {
        if end == 0 {
            break;
        }
        let search_region = &matched_string[..end];
        if let Some(colon_pos) = search_region.rfind(':') {
            let segment = &matched_string[colon_pos + 1..end];
            if !segment.is_empty() && segment.chars().all(|c| c.is_ascii_digit()) {
                numeric_segments.push((colon_pos, segment));
                end = colon_pos;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    numeric_segments.reverse();

    match numeric_segments.first() {
        None => (matched_string, None),
        Some(&(colon_pos, line_str)) => {
            let path = &matched_string[..colon_pos];
            (path, line_str.parse::<usize>().ok())
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- parse_path_and_line tests ---

    #[test]
    fn parse_path_and_line_simple_path() {
        let (path, line) = parse_path_and_line("src/main.rs");
        assert_eq!(path, "src/main.rs");
        assert_eq!(line, None);
    }

    #[test]
    fn parse_path_and_line_with_line_number() {
        let (path, line) = parse_path_and_line("src/main.rs:42");
        assert_eq!(path, "src/main.rs");
        assert_eq!(line, Some(42));
    }

    #[test]
    fn parse_path_and_line_with_line_and_col() {
        let (path, line) = parse_path_and_line("src/main.rs:42:10");
        assert_eq!(path, "src/main.rs");
        assert_eq!(line, Some(42));
    }

    #[test]
    fn parse_path_and_line_no_trailing_number() {
        let (path, line) = parse_path_and_line("src/main.rs:");
        assert_eq!(path, "src/main.rs:");
        assert_eq!(line, None);
    }

    // --- expand_path tests ---

    #[test]
    fn expand_path_tilde() {
        let mut env = BTreeMap::new();
        env.insert("HOME".into(), "/home/user".into());
        assert_eq!(expand_path("~/foo/bar", &env), "/home/user/foo/bar");
    }

    #[test]
    fn expand_path_env_var() {
        let mut env = BTreeMap::new();
        env.insert("HOME".into(), "/home/user".into());
        assert_eq!(expand_path("$HOME/foo", &env), "/home/user/foo");
    }

    #[test]
    fn expand_path_braced_var() {
        let mut env = BTreeMap::new();
        env.insert("HOME".into(), "/home/user".into());
        assert_eq!(expand_path("${HOME}/foo", &env), "/home/user/foo");
    }

    #[test]
    fn expand_path_unknown_var_preserved() {
        let env = BTreeMap::new();
        assert_eq!(expand_path("$UNKNOWN/foo", &env), "$UNKNOWN/foo");
    }

    #[test]
    fn expand_path_no_expansion_needed() {
        let env = BTreeMap::new();
        assert_eq!(expand_path("/absolute/path", &env), "/absolute/path");
    }

    // --- parse_url tests ---

    #[test]
    fn parse_url_plain() {
        assert_eq!(
            parse_url("https://github.com/zellij-org/zellij"),
            Some("https://github.com/zellij-org/zellij")
        );
        assert_eq!(parse_url("http://localhost:3000/path"), Some("http://localhost:3000/path"));
    }

    #[test]
    fn parse_url_trims_trailing_punctuation() {
        assert_eq!(parse_url("https://example.com/a)."), Some("https://example.com/a"));
        assert_eq!(parse_url("https://example.com/x,"), Some("https://example.com/x"));
        assert_eq!(parse_url("https://example.com/a)"), Some("https://example.com/a"));
    }

    #[test]
    fn parse_url_balanced_parentheses() {
        assert_eq!(
            parse_url("https://en.wikipedia.org/wiki/Worm_(search_engine)"),
            Some("https://en.wikipedia.org/wiki/Worm_(search_engine)")
        );
        assert_eq!(
            parse_url("https://en.wikipedia.org/wiki/Worm_(search_engine)."),
            Some("https://en.wikipedia.org/wiki/Worm_(search_engine)")
        );
        assert_eq!(
            parse_url("https://en.wikipedia.org/wiki/Worm_(search_engine))"),
            Some("https://en.wikipedia.org/wiki/Worm_(search_engine)")
        );
    }

    #[test]
    fn parse_url_rejects_non_urls() {
        assert_eq!(parse_url("/some/file/path"), None);
        assert_eq!(parse_url("~/code/nebelhaus"), None);
        assert_eq!(parse_url("httpsish://nope"), None);
    }

    // --- regex_escape tests ---

    #[test]
    fn regex_escape_special_chars() {
        assert_eq!(regex_escape("file.txt"), r"file\.txt");
        assert_eq!(regex_escape("a+b*c?"), r"a\+b\*c\?");
        assert_eq!(regex_escape("(foo)[bar]{baz}"), r"\(foo\)\[bar\]\{baz\}");
    }

    #[test]
    fn regex_escape_no_special_chars() {
        assert_eq!(regex_escape("foobar"), "foobar");
        assert_eq!(regex_escape("hello_world"), "hello_world");
    }

    // --- kdl_escape tests ---

    #[test]
    fn kdl_escape_quotes_and_backslashes() {
        assert_eq!(kdl_escape(r#"a"b\c"#), r#"a\"b\\c"#);
        assert_eq!(kdl_escape("/plain/path"), "/plain/path");
    }
}
