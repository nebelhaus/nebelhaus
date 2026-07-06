use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use zellij_tile::prelude::*;

const FILE_PATH_REGEX: &str = r#"(?:^|\s)((?:\./|\.\./|/)[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+|~/[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+)(?::\d+(?::\d+)?)?)(?::|\s|$)"#;

const CWD_CONTEXT_KEY: &str = "cwd";

#[derive(Default)]
struct State {
    known_terminal_panes: HashSet<PaneId>,
    pane_cwds: HashMap<PaneId, PathBuf>,
    env_vars: BTreeMap<String, String>,
}

thread_local! {
    static STATE: std::cell::RefCell<State> = std::cell::RefCell::new(Default::default());
}

#[no_mangle]
pub fn load() {
    std::panic::set_hook(Box::new(|info| {
        zellij_tile::shim::report_panic(info);
    }));

    STATE.with(|state| {
        use std::collections::BTreeMap;
        use std::convert::TryFrom;
        use zellij_tile::shim::plugin_api::action::ProtobufPluginConfiguration;
        use zellij_tile::shim::prost::Message;
        let protobuf_bytes: Vec<u8> = zellij_tile::shim::object_from_stdin().unwrap();
        let protobuf_configuration: ProtobufPluginConfiguration =
            ProtobufPluginConfiguration::decode(protobuf_bytes.as_slice()).unwrap();
        let plugin_configuration: BTreeMap<String, String> =
            BTreeMap::try_from(&protobuf_configuration).unwrap();
        state.borrow_mut().load(plugin_configuration);
    });
}

#[no_mangle]
pub fn update() -> bool {
    use std::convert::TryInto;
    use zellij_tile::shim::plugin_api::event::ProtobufEvent;
    use zellij_tile::shim::prost::Message;
    STATE.with(|state| {
        let protobuf_bytes: Vec<u8> = zellij_tile::shim::object_from_stdin().unwrap();
        let protobuf_event: ProtobufEvent =
            ProtobufEvent::decode(protobuf_bytes.as_slice()).unwrap();
        let event = protobuf_event.try_into().unwrap();
        state.borrow_mut().update(event)
    })
}

#[no_mangle]
pub fn pipe() -> bool {
    use std::convert::TryInto;
    use zellij_tile::shim::plugin_api::pipe_message::ProtobufPipeMessage;
    use zellij_tile::shim::prost::Message;
    STATE.with(|state| {
        let protobuf_bytes: Vec<u8> = zellij_tile::shim::object_from_stdin().unwrap();
        let protobuf_pipe_message: ProtobufPipeMessage =
            ProtobufPipeMessage::decode(protobuf_bytes.as_slice()).unwrap();
        let pipe_message = protobuf_pipe_message.try_into().unwrap();
        state.borrow_mut().pipe(pipe_message)
    })
}

#[no_mangle]
pub fn render(rows: i32, cols: i32) {
    STATE.with(|state| {
        state.borrow_mut().render(rows as usize, cols as usize);
    });
}

#[no_mangle]
pub fn plugin_version() {
    println!("{}", zellij_tile::prelude::VERSION);
}

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::FullHdAccess,
            PermissionType::ReadSessionEnvironmentVariables,
        ]);
        subscribe(&[
            EventType::PaneUpdate,
            EventType::HighlightClicked,
            EventType::CwdChanged,
        ]);
        change_host_folder(PathBuf::from("/"));
        self.env_vars = get_session_environment_variables();
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
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
        false
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // Background-only plugin.
    }
}

impl State {
    fn handle_pane_update(&mut self, pane_manifest: PaneManifest) {
        let mut current_panes = HashSet::new();

        for (_tab_index, panes) in &pane_manifest.panes {
            for pane_info in panes {
                if !pane_info.is_plugin {
                    let pane_id = PaneId::Terminal(pane_info.id);
                    current_panes.insert(pane_id);
                }
            }
        }

        for &pane_id in &current_panes {
            if !self.known_terminal_panes.contains(&pane_id) {
                if let Ok(cwd) = get_pane_cwd(pane_id) {
                    self.pane_cwds.insert(pane_id, cwd);
                }
                self.set_highlights_for_pane(pane_id);
            }
        }

        for &pane_id in &self.known_terminal_panes {
            if !current_panes.contains(&pane_id) {
                self.pane_cwds.remove(&pane_id);
            }
        }

        self.known_terminal_panes = current_panes;
    }

    fn handle_cwd_changed(&mut self, pane_id: PaneId, new_cwd: PathBuf) {
        let old_cwd = self.pane_cwds.get(&pane_id);
        if old_cwd == Some(&new_cwd) {
            return;
        }

        self.pane_cwds.insert(pane_id, new_cwd);
        clear_pane_highlights(pane_id);
        self.set_highlights_for_pane(pane_id);
    }

    fn handle_highlight_clicked(&self, matched_string: String, context: BTreeMap<String, String>) {
        let (path_str, _) = parse_path_and_line(&matched_string);
        let path_str = path_str.trim();
        let expanded = expand_path(path_str, &self.env_vars);
        let path_str = expanded.as_str();

        let absolute_path = if path_str.starts_with('/') {
            PathBuf::from(path_str)
        } else if let Some(cwd) = context.get(CWD_CONTEXT_KEY) {
            PathBuf::from(cwd).join(path_str)
        } else {
            PathBuf::from(path_str)
        };

        // Validate that path exists via host mount
        let host_path = Path::new("/host").join(absolute_path.strip_prefix("/").unwrap_or(&absolute_path));
        let metadata = match std::fs::metadata(&host_path) {
            Ok(m) => m,
            Err(_) => return, // path does not exist
        };

        // Determine directory to open in new tab
        let dir_path = if metadata.is_dir() {
            absolute_path.clone()
        } else {
            match absolute_path.parent() {
                Some(p) => p.to_path_buf(),
                None => return,
            }
        };

        // Find git root starting from dir_path
        let mut git_root = None;
        let mut current = dir_path.clone();
        loop {
            let host_parent_git = Path::new("/host")
                .join(current.strip_prefix("/").unwrap_or(&current))
                .join(".git");
            if std::fs::metadata(&host_parent_git).is_ok() {
                git_root = Some(current.clone());
                break;
            }
            if !current.pop() {
                break;
            }
        }

        // Get name of the tab based on git root or directory basename
        let name = if let Some(ref root) = git_root {
            root.file_name()
                .map(|f| f.to_string_lossy().into_owned())
                .unwrap_or_else(|| "zellij-tab".to_string())
        } else {
            dir_path
                .file_name()
                .map(|f| f.to_string_lossy().into_owned())
                .unwrap_or_else(|| "zellij-tab".to_string())
        };

        let cwd_escaped = dir_path.to_string_lossy().replace('\\', "\\\\").replace('"', "\\\"");
        let name_escaped = name.replace('\\', "\\\\").replace('"', "\\\"");

        // Construct KDL layout using custom tab layout (incorporating tab-bar and status-bar)
        let layout_kdl = format!(
            r#"
            layout {{
                default_tab_template {{
                    pane size=1 borderless=true {{
                        plugin location="zellij:tab-bar"
                    }}
                    children
                    pane size=1 borderless=true {{
                        plugin location="zellij:status-bar"
                    }}
                }}
                tab cwd="{}" name="{}" {{
                    pane
                }}
            }}
            "#,
            cwd_escaped, name_escaped
        );

        new_tabs_with_layout(&layout_kdl);
    }

    fn set_highlights_for_pane(&self, pane_id: PaneId) {
        let mut highlights = Vec::new();
        let mut context = BTreeMap::new();

        if let Some(cwd) = self.pane_cwds.get(&pane_id) {
            context.insert(CWD_CONTEXT_KEY.to_string(), cwd.to_string_lossy().into_owned());
        }

        highlights.push(RegexHighlight {
            pattern: FILE_PATH_REGEX.to_owned(),
            style: HighlightStyle::None,
            layer: HighlightLayer::Hint,
            context,
            on_hover: true,
            bold: false,
            italic: true,
            underline: true,
            tooltip_text: Some("Open in new tab".to_string()),
        });

        set_pane_regex_highlights(pane_id, highlights);
    }
}

fn parse_path_and_line(matched_string: &str) -> (&str, Option<usize>) {
    let mut end = matched_string.len();
    let mut numeric_segments = Vec::new();

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

fn expand_path(path: &str, env_vars: &BTreeMap<String, String>) -> String {
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

    let bytes = after_tilde.as_bytes();
    let len = bytes.len();
    let mut result = String::with_capacity(len);
    let mut i = 0;

    while i < len {
        if bytes[i] == b'$' && i + 1 < len {
            let (var_name, end_idx) = if bytes[i + 1] == b'{' {
                if let Some(close) = after_tilde[i + 2..].find('}') {
                    let name = &after_tilde[i + 2..i + 2 + close];
                    (name, i + 2 + close + 1)
                } else {
                    result.push('$');
                    i += 1;
                    continue;
                }
            } else {
                let start = i + 1;
                if start < len && ((bytes[start] as char).is_ascii_alphabetic() || bytes[start] == b'_') {
                    let mut end = start + 1;
                    while end < len && ((bytes[end] as char).is_ascii_alphanumeric() || bytes[end] == b'_') {
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
