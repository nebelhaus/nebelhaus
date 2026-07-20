use ansi_term::{ANSIString, ANSIStrings};
use ansi_term::{
    Color::{Fixed, RGB},
    Style,
};
use std::collections::HashMap;
use zellij_tile::prelude::actions::Action;
use zellij_tile::prelude::*;
use zellij_tile_utils::palette_match;

use crate::first_line::{to_char, KeyAction, KeyMode, KeyShortcut};
use crate::second_line::{system_clipboard_error, text_copied_hint};
use crate::{action_key, action_key_group, color_elements, MORE_MSG, TO_NORMAL};
use crate::{ColoredElements, LinePart};
use unicode_width::UnicodeWidthStr;

pub fn one_line_ui(
    help: &ModeInfo,
    tab_info: Option<&TabInfo>,
    mut max_len: usize,
    separator: &str,
    base_mode_is_locked: bool,
    text_copied_to_clipboard_destination: Option<CopyDestination>,
    clipboard_failure: bool,
) -> LinePart {
    if let Some(text_copied_to_clipboard_destination) = text_copied_to_clipboard_destination {
        return text_copied_hint(text_copied_to_clipboard_destination);
    }
    if clipboard_failure {
        return system_clipboard_error(&help.style.colors);
    }
    let mut line_part_to_render = LinePart::default();
    let mut append = |line_part: &LinePart, max_len: &mut usize| {
        line_part_to_render.append(line_part);
        *max_len = max_len.saturating_sub(line_part.len);
    };

    render_mode_key_indicators(help, max_len, separator, base_mode_is_locked)
        .map(|mode_key_indicators| append(&mode_key_indicators, &mut max_len))
        .and_then(|_| match help.mode {
            // Unlocked (Normal): the full mode ribbon on the left already spells
            // out every submode, so the bottom-right `Super + <c,p,t,y>` launcher
            // block is just clutter here — leave the right side empty. The hints
            // still render in Locked, where the ribbon collapses to the lone
            // unlock key and the reminder earns its space.
            InputMode::Normal => Some(()),
            InputMode::Locked => render_secondary_info(help, tab_info, max_len)
                .map(|secondary_info| append(&secondary_info, &mut max_len)),
            _ => add_keygroup_separator(help, max_len)
                .map(|key_group_separator| append(&key_group_separator, &mut max_len))
                .and_then(|_| keybinds(help, max_len))
                .map(|keybinds| append(&keybinds, &mut max_len)),
        });
    line_part_to_render
}

fn to_base_mode(base_mode: InputMode) -> Action {
    Action::SwitchToMode {
        input_mode: base_mode,
    }
}

fn base_mode_locked_mode_indicators(help: &ModeInfo) -> HashMap<InputMode, Vec<KeyShortcut>> {
    let locked_binds = &help.get_keybinds_for_mode(InputMode::Locked);
    let normal_binds = &help.get_keybinds_for_mode(InputMode::Normal);
    let pane_binds = &help.get_keybinds_for_mode(InputMode::Pane);
    let tab_binds = &help.get_keybinds_for_mode(InputMode::Tab);
    let resize_binds = &help.get_keybinds_for_mode(InputMode::Resize);
    let move_binds = &help.get_keybinds_for_mode(InputMode::Move);
    let scroll_binds = &help.get_keybinds_for_mode(InputMode::Scroll);
    let session_binds = &help.get_keybinds_for_mode(InputMode::Session);
    HashMap::from([
        (
            InputMode::Locked,
            vec![KeyShortcut::new(
                KeyMode::Unselected,
                KeyAction::Unlock,
                to_char(action_key(
                    locked_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Normal,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Pane,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Pane,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Tab,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Tab,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Resize,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Resize,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Move,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Move,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Search,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Scroll,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Session,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Session,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Quit,
                    to_char(action_key(normal_binds, &[Action::Quit])),
                ),
            ],
        ),
        (
            InputMode::Pane,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        pane_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Pane,
                    to_char(action_key(
                        pane_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Tab,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        tab_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Tab,
                    to_char(action_key(
                        tab_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Resize,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        resize_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Resize,
                    to_char(action_key(
                        resize_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Move,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        move_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Move,
                    to_char(action_key(
                        move_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Scroll,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        scroll_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Search,
                    to_char(action_key(
                        scroll_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
        (
            InputMode::Session,
            vec![
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Unlock,
                    to_char(action_key(
                        session_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Selected,
                    KeyAction::Session,
                    to_char(action_key(
                        session_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Normal,
                        }],
                    )),
                ),
            ],
        ),
    ])
}

fn base_mode_normal_mode_indicators(help: &ModeInfo) -> HashMap<InputMode, Vec<KeyShortcut>> {
    let locked_binds = &help.get_keybinds_for_mode(InputMode::Locked);
    let normal_binds = &help.get_keybinds_for_mode(InputMode::Normal);
    let pane_binds = &help.get_keybinds_for_mode(InputMode::Pane);
    let tab_binds = &help.get_keybinds_for_mode(InputMode::Tab);
    let resize_binds = &help.get_keybinds_for_mode(InputMode::Resize);
    let move_binds = &help.get_keybinds_for_mode(InputMode::Move);
    let scroll_binds = &help.get_keybinds_for_mode(InputMode::Scroll);
    let session_binds = &help.get_keybinds_for_mode(InputMode::Session);
    HashMap::from([
        (
            InputMode::Locked,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Lock,
                to_char(action_key(
                    locked_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Normal,
            vec![
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Lock,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Locked,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Pane,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Pane,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Tab,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Tab,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Resize,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Resize,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Move,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Move,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Search,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Scroll,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::Unselected,
                    KeyAction::Session,
                    to_char(action_key(
                        normal_binds,
                        &[Action::SwitchToMode {
                            input_mode: InputMode::Session,
                        }],
                    )),
                ),
                KeyShortcut::new(
                    KeyMode::UnselectedAlternate,
                    KeyAction::Quit,
                    to_char(action_key(normal_binds, &[Action::Quit])),
                ),
            ],
        ),
        (
            InputMode::Pane,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Pane,
                to_char(action_key(
                    pane_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Tab,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Tab,
                to_char(action_key(
                    tab_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Resize,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Resize,
                to_char(action_key(
                    resize_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Move,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Move,
                to_char(action_key(
                    move_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Scroll,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Search,
                to_char(action_key(
                    scroll_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
        (
            InputMode::Session,
            vec![KeyShortcut::new(
                KeyMode::Selected,
                KeyAction::Session,
                to_char(action_key(
                    session_binds,
                    &[Action::SwitchToMode {
                        input_mode: InputMode::Normal,
                    }],
                )),
            )],
        ),
    ])
}

fn render_mode_key_indicators(
    help: &ModeInfo,
    max_len: usize,
    separator: &str,
    base_mode_is_locked: bool,
) -> Option<LinePart> {
    let mut line_part_to_render = LinePart::default();
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let colored_elements = color_elements(help.style.colors, !supports_arrow_fonts);
    let default_keys = if base_mode_is_locked {
        base_mode_locked_mode_indicators(help)
    } else {
        base_mode_normal_mode_indicators(help)
    };
    match common_modifiers_in_all_modes(&default_keys) {
        Some(modifiers) => {
            if let Some(default_keys) = default_keys.get(&help.mode) {
                let keys_without_common_modifiers: Vec<KeyShortcut> = default_keys
                    .iter()
                    .map(|key_shortcut| {
                        let key = key_shortcut
                            .get_key()
                            .map(|k| k.strip_common_modifiers(&modifiers));
                        let mode = key_shortcut.get_mode();
                        let action = key_shortcut.get_action();
                        KeyShortcut::new(mode, action, key)
                    })
                    .collect();
                // Fork: render the " Ctrl +" prefix into a scratch LinePart and
                // only commit it TOGETHER with a shortcut list that fits. The
                // upstream code appended the prefix unconditionally, so in a thin
                // pane where neither the full nor the shortened list fits you got
                // a dangling " Ctrl +" with nothing after it — the "broken bar"
                // look. Now that case renders nothing on the left instead.
                let mut modifier_prefix = LinePart::default();
                render_common_modifiers(
                    &colored_elements,
                    help,
                    &modifiers,
                    &mut modifier_prefix,
                    separator,
                );

                let full_shortcut_list =
                    full_inline_keys_modes_shortcut_list(&keys_without_common_modifiers, help);

                if modifier_prefix.len + full_shortcut_list.len <= max_len {
                    line_part_to_render.append(&modifier_prefix);
                    line_part_to_render.append(&full_shortcut_list);
                } else {
                    let shortened_shortcut_list = shortened_inline_keys_modes_shortcut_list(
                        &keys_without_common_modifiers,
                        help,
                    );
                    if modifier_prefix.len + shortened_shortcut_list.len <= max_len {
                        line_part_to_render.append(&modifier_prefix);
                        line_part_to_render.append(&shortened_shortcut_list);
                    }
                }
            }
        },
        None => {
            if let Some(default_keys) = default_keys.get(&help.mode) {
                let full_shortcut_list = full_modes_shortcut_list(&default_keys, help);
                if line_part_to_render.len + full_shortcut_list.len <= max_len {
                    line_part_to_render.append(&full_shortcut_list);
                } else {
                    let shortened_shortcut_list =
                        shortened_modes_shortcut_list(&default_keys, help);
                    if line_part_to_render.len + shortened_shortcut_list.len <= max_len {
                        line_part_to_render.append(&shortened_shortcut_list);
                    }
                }
            }
        },
    }
    if line_part_to_render.len <= max_len {
        Some(line_part_to_render)
    } else {
        None
    }
}

fn full_inline_keys_modes_shortcut_list(
    keys_without_common_modifiers: &Vec<KeyShortcut>,
    help: &ModeInfo,
) -> LinePart {
    let mut full_shortcut_list = LinePart::default();
    for key in keys_without_common_modifiers {
        let keys = key
            .key
            .as_ref()
            .map(|k| vec![k.clone()])
            .unwrap_or_else(|| vec![]);
        let shortcut = if is_selected_lock(key) {
            add_locked_shortcut_with_inline_key(help, &key.full_text(), keys)
        } else {
            add_shortcut_with_inline_key(help, &key.full_text(), keys, key.is_selected())
        };
        full_shortcut_list.append(&shortcut);
    }
    full_shortcut_list
}

fn shortened_inline_keys_modes_shortcut_list(
    keys_without_common_modifiers: &Vec<KeyShortcut>,
    help: &ModeInfo,
) -> LinePart {
    let mut shortened_shortcut_list = LinePart::default();
    for key in keys_without_common_modifiers {
        let keys = key
            .key
            .as_ref()
            .map(|k| vec![k.clone()])
            .unwrap_or_else(|| vec![]);
        let shortcut = if is_selected_lock(key) {
            add_locked_shortcut_with_key_only(help, keys)
        } else {
            add_shortcut_with_key_only(help, keys, key.is_selected())
        };
        shortened_shortcut_list.append(&shortcut);
    }
    shortened_shortcut_list
}

fn full_modes_shortcut_list(default_keys: &Vec<KeyShortcut>, help: &ModeInfo) -> LinePart {
    let mut full_shortcut_list = LinePart::default();
    for key in default_keys {
        let keys = key
            .key
            .as_ref()
            .map(|k| vec![k.clone()])
            .unwrap_or_else(|| vec![]);
        if is_selected_lock(key) {
            // key styled separately (as in add_shortcut), then a red label pill
            full_shortcut_list.append(&style_key_with_modifier(&keys, Some(3)));
            full_shortcut_list.append(&add_locked_label_ribbon(help, &key.full_text()));
        } else {
            full_shortcut_list.append(&add_shortcut(
                help,
                &key.full_text(),
                &keys,
                key.is_selected(),
                Some(3),
            ));
        }
    }
    full_shortcut_list
}

fn shortened_modes_shortcut_list(default_keys: &Vec<KeyShortcut>, help: &ModeInfo) -> LinePart {
    let mut shortened_shortcut_list = LinePart::default();
    for key in default_keys {
        let keys = key
            .key
            .as_ref()
            .map(|k| vec![k.clone()])
            .unwrap_or_else(|| vec![]);
        if is_selected_lock(key) {
            shortened_shortcut_list.append(&style_key_with_modifier(&keys, Some(3)));
            shortened_shortcut_list.append(&add_locked_label_ribbon(help, &key.short_text()));
        } else {
            shortened_shortcut_list.append(&add_shortcut(
                help,
                &key.short_text(),
                &keys,
                key.is_selected(),
                Some(3),
            ));
        }
    }
    shortened_shortcut_list
}

fn common_modifiers_in_all_modes(
    key_shortcuts: &HashMap<InputMode, Vec<KeyShortcut>>,
) -> Option<Vec<KeyModifier>> {
    let Some(mut common_modifiers) = key_shortcuts.iter().next().and_then(|k| {
        k.1.iter()
            .next()
            .and_then(|k| k.get_key().map(|k| k.key_modifiers.clone()))
    }) else {
        return None;
    };
    for (_mode, key_shortcuts) in key_shortcuts {
        if key_shortcuts.is_empty() {
            return None;
        }
        let Some(mut common_modifiers_for_mode) = key_shortcuts
            .iter()
            .next()
            .unwrap()
            .get_key()
            .map(|k| k.key_modifiers.clone())
        else {
            return None;
        };
        for key in key_shortcuts {
            let Some(key) = key.get_key() else {
                return None;
            };
            common_modifiers_for_mode = common_modifiers_for_mode
                .intersection(&key.key_modifiers)
                .cloned()
                .collect();
        }
        common_modifiers = common_modifiers
            .intersection(&common_modifiers_for_mode)
            .cloned()
            .collect();
    }
    if common_modifiers.is_empty() {
        return None;
    }
    Some(common_modifiers.into_iter().collect())
}

fn render_common_modifiers(
    palette: &ColoredElements,
    mode_info: &ModeInfo,
    common_modifiers: &Vec<KeyModifier>,
    line_part_to_render: &mut LinePart,
    separator: &str,
) {
    let prefix_text = if mode_info.capabilities.arrow_fonts {
        // Add extra space in simplified ui
        format!(
            " {} + ",
            common_modifiers
                .iter()
                .map(|m| m.to_string())
                .collect::<Vec<_>>()
                .join("-")
        )
    } else {
        format!(
            " {} +",
            common_modifiers
                .iter()
                .map(|m| m.to_string())
                .collect::<Vec<_>>()
                .join("-")
        )
    };

    let suffix_separator = palette.superkey_suffix_separator.paint(separator);
    line_part_to_render.part = format!(
        "{}{}{}",
        line_part_to_render.part,
        serialize_text(&Text::new(&prefix_text).opaque()),
        suffix_separator
    );
    line_part_to_render.len += prefix_text.chars().count() + separator.chars().count();
}

fn render_secondary_info(
    help: &ModeInfo,
    tab_info: Option<&TabInfo>,
    max_len: usize,
) -> Option<LinePart> {
    let mut secondary_info = LinePart::default();
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let colored_elements = color_elements(help.style.colors, !supports_arrow_fonts);
    let secondary_keybinds = secondary_keybinds(&help, tab_info, max_len);
    secondary_info.append(&secondary_keybinds);
    let remaining_space = max_len.saturating_sub(secondary_info.len).saturating_sub(1); // 1 for the end padding of the line
    let mut padding = String::new();
    let mut padding_len = 0;
    for _ in 0..remaining_space {
        padding.push_str(&ANSIStrings(&[colored_elements.superkey_prefix.paint(" ")]).to_string());
        padding_len += 1;
    }
    secondary_info.part = format!("{}{}", padding, secondary_info.part);
    secondary_info.len += padding_len;
    if secondary_info.len <= max_len {
        Some(secondary_info)
    } else {
        None
    }
}

fn should_show_focus_and_resize_shortcuts(tab_info: Option<&TabInfo>) -> bool {
    let Some(tab_info) = tab_info else {
        return false;
    };
    let are_floating_panes_visible = tab_info.are_floating_panes_visible;
    if are_floating_panes_visible {
        tab_info.selectable_floating_panes_count > 1
    } else {
        tab_info.selectable_tiled_panes_count > 1
    }
}

fn secondary_keybinds(help: &ModeInfo, _tab_info: Option<&TabInfo>, max_len: usize) -> LinePart {
    let binds = &help.get_mode_keybinds();
    // Fork: the bottom-right quick hints are condensed to a single flat block —
    // ` Super + <c,p,t,y> ` — the four launchers only (c = claude --worktree,
    // p = new pane, t = new tab, y = yazi peek): keys only, no word-labels and
    // no powerline ribbons. What each key does lives in the web docs /
    // cheatsheet (nebelhaus.com), not spelled out on the bar. Keys are still
    // resolved from the live binds (via run_bind_key / action_key), so a rebind
    // re-letters the block; only the labels and the Floating/Focus/Resize hints
    // were dropped versus upstream.
    let claude_key = run_bind_key(binds, "claude", Some("--worktree"));
    let peek_key = run_bind_key(binds, "peek.sh", None);

    let new_pane_action_key = action_key(
        binds,
        &[Action::NewPane {
            direction: None,
            pane_name: None,
            start_suppressed: false,
        }],
    );
    let pane_key = new_pane_action_key
        .iter()
        .find(|k| k.is_key_with_alt_modifier(BareKey::Char('n')))
        .or_else(|| new_pane_action_key.iter().next())
        .map(|k| vec![k.clone()])
        .unwrap_or_default();

    // New Tab: Super-t carries the NewTab action (Super-Shift-t is a `Run` —
    // new-tab-here.sh — not a NewTab, so it never matches here). Prefer the
    // un-shifted key so the hint reads `t`, never `Shift t` (the old bug: both
    // t-binds matched NewTab and the shifted one won the `.next()` race).
    let new_tab_action_key = action_key(
        binds,
        &[Action::NewTab {
            tiled_layout: None,
            floating_layouts: vec![],
            swap_tiled_layouts: None,
            swap_floating_layouts: None,
            tab_name: None,
            should_change_focus_to_new_tab: true,
            cwd: None,
            initial_panes: None,
            first_pane_unblock_condition: None,
        }],
    );
    let tab_key = new_tab_action_key
        .iter()
        .find(|k| k.bare_key == BareKey::Char('t') && !k.key_modifiers.contains(&KeyModifier::Shift))
        .or_else(|| new_tab_action_key.iter().find(|k| k.bare_key == BareKey::Char('t')))
        .or_else(|| new_tab_action_key.iter().next())
        .map(|k| vec![k.clone()])
        .unwrap_or_default();

    // Order on the bar: c, p, t, y.
    let ordered: Vec<Vec<KeyWithModifier>> = vec![claude_key, pane_key, tab_key, peek_key];
    let common_modifiers = get_common_modifiers(ordered.iter().flatten().collect());

    // One display char per launcher, common modifier stripped so only `c`/`p`/…
    // shows inside the bracket group.
    let key_chars: Vec<String> = ordered
        .iter()
        .filter_map(|k| {
            k.first().map(|k| {
                if common_modifiers.is_empty() {
                    k.to_string()
                } else {
                    k.strip_common_modifiers(&common_modifiers).to_string()
                }
            })
        })
        .collect();

    if key_chars.is_empty() {
        return LinePart::default();
    }
    let joined = key_chars.join(",");

    // ` <mods> + <c,p,t,y> ` as one opaque, non-ribbon block; the bracket group
    // is painted in the emphasis colour (index 0). On a pane too thin for the
    // modifier prefix, fall back to a bare ` <c,p,t,y> `.
    let render_block = |with_modifier: bool| -> LinePart {
        let prefix = if with_modifier && !common_modifiers.is_empty() {
            format!(
                " {} + ",
                common_modifiers
                    .iter()
                    .map(|m| m.to_string())
                    .collect::<Vec<_>>()
                    .join("-")
            )
        } else {
            " ".to_string()
        };
        let bracket = format!("<{}>", joined);
        let full = format!("{}{} ", prefix, bracket);
        let start = prefix.width();
        let end = start + bracket.width();
        LinePart {
            part: serialize_text(&Text::new(&full).color_range(0, start..end).opaque()),
            len: full.width(),
        }
    };

    let full_block = render_block(true);
    if full_block.len <= max_len {
        full_block
    } else {
        render_block(false)
    }
}
fn text_as_line_part_with_emphasis(text: String, emphases_index: usize) -> LinePart {
    let part = serialize_text(&Text::new(&text).color_range(emphases_index, ..).opaque());
    LinePart {
        part,
        len: text.width(),
    }
}

fn keybinds(help: &ModeInfo, max_width: usize) -> Option<LinePart> {
    let full_shortcut_list = full_shortcut_list(help);
    if full_shortcut_list.len <= max_width {
        return Some(full_shortcut_list);
    }
    let shortened_shortcut_list = shortened_shortcut_list(help);
    if shortened_shortcut_list.len <= max_width {
        return Some(shortened_shortcut_list);
    }
    Some(best_effort_shortcut_list(help, max_width))
}

fn add_shortcut(
    help: &ModeInfo,
    text: &str,
    keys: &Vec<KeyWithModifier>,
    selected: bool,
    key_color_index: Option<usize>,
) -> LinePart {
    let mut ret = LinePart::default();
    if keys.is_empty() {
        return ret;
    }

    ret.append(&style_key_with_modifier(&keys, key_color_index)); // TODO: alternate
                                                                  //
    let ribbon = if selected {
        serialize_ribbon(&Text::new(format!("{}", text)).selected())
    } else {
        serialize_ribbon(&Text::new(format!("{}", text)))
    };
    ret.part = format!("{}{}", ret.part, ribbon);
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    ret.len += if supports_arrow_fonts {
        text.width() + 4 // padding and arrow fonts
    } else {
        text.width() + 2 // padding
    };
    ret
}

fn add_shortcut_with_inline_key(
    help: &ModeInfo,
    text: &str,
    key: Vec<KeyWithModifier>,
    is_selected: bool,
) -> LinePart {
    let capabilities = help.capabilities;

    let mut ret = LinePart::default();
    if key.is_empty() {
        return ret;
    }

    let key_separator = match key
        .iter()
        .map(|k| k.to_string())
        .collect::<Vec<_>>()
        .join("")
        .as_str()
    {
        "HJKL" => "",
        "hjkl" => "",
        "←↓↑→" => "",
        "←→" => "",
        "↓↑" => "",
        "[]" => "",
        "+-" => "",
        _ => "|",
    };

    let key_string = format!(
        "{}",
        key.iter()
            .map(|k| k.to_string())
            .collect::<Vec<_>>()
            .join(key_separator)
    );

    let ribbon = if is_selected {
        serialize_ribbon(
            &Text::new(format!("<{}> {}", key_string, text))
                .color_range(0, 1..key_string.width() + 1)
                .selected(),
        )
    } else {
        serialize_ribbon(
            &Text::new(format!("<{}> {}", key_string, text))
                .color_range(0, 1..key_string.width() + 1),
        )
    };
    ret.part = ribbon;
    let supports_arrow_fonts = !capabilities.arrow_fonts;
    ret.len += if supports_arrow_fonts {
        text.width() + key_string.width() + 7 // padding, group boundaries and arrow fonts
    } else {
        text.width() + key_string.width() + 5 // padding and group boundaries
    };

    ret
}

// Fork: find the key bound to a `Run` command, so the bottom-right hints can
// surface our custom launchers (claude --worktree, yazi peek) next to New Pane
// / New Tab. Matches on the command basename (+ an optional required arg) so a
// rebind (e.g. Super c / Super y) still resolves.
//
// Gotcha: a `bind { Run "…"; }` does NOT reach a plugin as `Action::Run`.
// zellij rewrites a Run keybind into the pane it opens before handing the
// keybinds to plugins — a tiled `Run` arrives as `NewTiledPane { command:
// Some(RunCommandAction) }`, a floating one as `NewFloatingPane { … }`. The
// RunCommandAction (command + args) rides along inside, so we match those
// variants (plus a bare `Run`, for safety) on the carried command.
fn run_bind_key(
    binds: &[(KeyWithModifier, Vec<Action>)],
    file_name: &str,
    required_arg: Option<&str>,
) -> Vec<KeyWithModifier> {
    binds
        .iter()
        .find_map(|(key, actions)| {
            actions.iter().find_map(|a| {
                let cmd = match a {
                    Action::Run { command, .. } => Some(command),
                    Action::NewTiledPane { command, .. }
                    | Action::NewFloatingPane { command, .. }
                    | Action::NewInPlacePane { command, .. } => command.as_ref(),
                    _ => None,
                };
                cmd.filter(|c| {
                    c.command.file_name().and_then(|n| n.to_str()) == Some(file_name)
                        && required_arg.map_or(true, |ra| c.args.iter().any(|arg| arg == ra))
                })
                .map(|_| vec![key.clone()])
            })
        })
        .unwrap_or_default()
}

fn add_shortcut_with_key_only(
    help: &ModeInfo,
    key: Vec<KeyWithModifier>,
    is_selected: bool,
) -> LinePart {
    let mut ret = LinePart::default();
    if key.is_empty() {
        return ret;
    }

    let key_string = format!(
        "{}",
        key.iter()
            .map(|k| k.to_string())
            .collect::<Vec<_>>()
            .join("-")
    );

    let ribbon = if is_selected {
        serialize_ribbon(
            &Text::new(format!("{}", key_string))
                .color_range(0, ..)
                .selected(),
        )
    } else {
        serialize_ribbon(&Text::new(format!("{}", key_string)).color_range(0, ..))
    };
    ret.part = ribbon;
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    ret.len += if supports_arrow_fonts {
        key_string.width() + 4 // 4 => arrow fonts + padding
    } else {
        key_string.width() + 2 // 2 => padding
    };
    ret
}

// Fork: the "locked" mode indicator (`<g> LOCK` / `<g> UNLOCK`) reads as a
// mellow red instead of the shared green when selected — locking is a distinct,
// slightly-alarming state, so it gets its own accent while every other selected
// mode (PANE, TAB, …) keeps the green `ribbon_selected` look. zellij's ribbon
// DCS escape only ever paints the theme's `ribbon_selected`/`ribbon_unselected`
// background, so a red pill can't go through `serialize_ribbon` — we hand-roll it
// with ansi_term (same technique as `add_keygroup_separator`). The red is the
// nebelung theme's own `exit_code_error.base` (#ed8fa9), with its `emphasis_0`
// (#f7e2b5, yellow) accenting the key letter — no new palette slots needed.
fn locked_ribbon_colors(palette: Styling) -> (ansi_term::Color, ansi_term::Color, ansi_term::Color, ansi_term::Color) {
    let red_bg = palette_match!(palette.exit_code_error.base);
    let dark_fg = palette_match!(palette.ribbon_selected.base);
    let key_fg = palette_match!(palette.exit_code_error.emphasis_0);
    let line_bg = palette_match!(palette.text_unselected.background);
    (red_bg, dark_fg, key_fg, line_bg)
}

// Red counterpart of `add_shortcut_with_inline_key` — ` <g> LOCK ` in one pill.
fn add_locked_shortcut_with_inline_key(
    help: &ModeInfo,
    text: &str,
    key: Vec<KeyWithModifier>,
) -> LinePart {
    if key.is_empty() {
        return add_locked_label_ribbon(help, text);
    }
    let (red_bg, dark_fg, key_fg, line_bg) = locked_ribbon_colors(help.style.colors);
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let separator = if supports_arrow_fonts {
        crate::ARROW_SEPARATOR
    } else {
        ""
    };
    let key_string = key
        .iter()
        .map(|k| k.to_string())
        .collect::<Vec<_>>()
        .join("|");
    let bits: Vec<ANSIString> = vec![
        Style::new().fg(line_bg).on(red_bg).paint(separator),
        Style::new().fg(dark_fg).on(red_bg).bold().paint(" <"),
        Style::new()
            .fg(key_fg)
            .on(red_bg)
            .bold()
            .paint(key_string.clone()),
        Style::new()
            .fg(dark_fg)
            .on(red_bg)
            .bold()
            .paint(format!("> {} ", text)),
        Style::new().fg(red_bg).on(line_bg).paint(separator),
    ];
    let len = if supports_arrow_fonts {
        text.width() + key_string.width() + 7
    } else {
        text.width() + key_string.width() + 5
    };
    LinePart {
        part: ANSIStrings(&bits).to_string(),
        len,
    }
}

// Red counterpart of `add_shortcut_with_key_only` — just ` g ` in a red pill.
fn add_locked_shortcut_with_key_only(help: &ModeInfo, key: Vec<KeyWithModifier>) -> LinePart {
    if key.is_empty() {
        return LinePart::default();
    }
    let (red_bg, _dark_fg, key_fg, line_bg) = locked_ribbon_colors(help.style.colors);
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let separator = if supports_arrow_fonts {
        crate::ARROW_SEPARATOR
    } else {
        ""
    };
    let key_string = key
        .iter()
        .map(|k| k.to_string())
        .collect::<Vec<_>>()
        .join("-");
    let bits: Vec<ANSIString> = vec![
        Style::new().fg(line_bg).on(red_bg).paint(separator),
        Style::new()
            .fg(key_fg)
            .on(red_bg)
            .bold()
            .paint(format!(" {} ", key_string)),
        Style::new().fg(red_bg).on(line_bg).paint(separator),
    ];
    let len = if supports_arrow_fonts {
        key_string.width() + 4
    } else {
        key_string.width() + 2
    };
    LinePart {
        part: ANSIStrings(&bits).to_string(),
        len,
    }
}

// Red LOCK label pill, no inline key (the key is styled separately alongside it,
// as in `add_shortcut`). Used on the no-common-modifier rendering path.
fn add_locked_label_ribbon(help: &ModeInfo, text: &str) -> LinePart {
    let (red_bg, dark_fg, _key_fg, line_bg) = locked_ribbon_colors(help.style.colors);
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let separator = if supports_arrow_fonts {
        crate::ARROW_SEPARATOR
    } else {
        ""
    };
    let bits: Vec<ANSIString> = vec![
        Style::new().fg(line_bg).on(red_bg).paint(separator),
        Style::new()
            .fg(dark_fg)
            .on(red_bg)
            .bold()
            .paint(format!(" {} ", text)),
        Style::new().fg(red_bg).on(line_bg).paint(separator),
    ];
    let len = if supports_arrow_fonts {
        text.width() + 4
    } else {
        text.width() + 2
    };
    LinePart {
        part: ANSIStrings(&bits).to_string(),
        len,
    }
}

// Fork: is this mode indicator the (un)lock pill in its selected state? Those get
// the red treatment above; everything else stays on the shared green ribbon.
fn is_selected_lock(key: &KeyShortcut) -> bool {
    key.is_selected() && matches!(key.get_action(), KeyAction::Lock | KeyAction::Unlock)
}

fn add_keygroup_separator(help: &ModeInfo, max_len: usize) -> Option<LinePart> {
    let supports_arrow_fonts = !help.capabilities.arrow_fonts;
    let separator = if supports_arrow_fonts {
        crate::ARROW_SEPARATOR
    } else {
        " "
    };
    let palette = help.style.colors;

    let mut ret = LinePart::default();

    let separator_color = palette_match!(palette.text_unselected.emphasis_0);
    let bg_color = palette_match!(palette.ribbon_selected.base);
    let mut bits: Vec<ANSIString> = vec![];
    let mode_help_text = match help.mode {
        InputMode::RenamePane => Some("RENAMING PANE"),
        InputMode::RenameTab => Some("RENAMING TAB"),
        InputMode::EnterSearch => Some("ENTERING SEARCH TERM"),
        InputMode::Search => Some("SEARCHING"),
        _ => None,
    };
    if let Some(mode_help_text) = mode_help_text {
        bits.push(
            Style::new()
                .fg(separator_color)
                .on(bg_color)
                .bold()
                .paint(format!(" {} ", mode_help_text)),
        );
        ret.len += mode_help_text.width() + 2; // 2 => padding
    }
    bits.push(
        Style::new()
            .fg(bg_color)
            .on(separator_color)
            .bold()
            .paint(format!("{}", separator)),
    );
    bits.push(
        Style::new()
            .fg(separator_color)
            .on(separator_color)
            .bold()
            .paint(format!(" ")),
    );
    bits.push(
        Style::new()
            .fg(separator_color)
            .on(bg_color)
            .bold()
            .paint(format!("{}", separator)),
    );
    ret.part = format!("{}{}", ret.part, ANSIStrings(&bits));
    ret.len += 3; // padding and arrow fonts

    if ret.len <= max_len {
        Some(ret)
    } else {
        None
    }
}

fn full_shortcut_list(help: &ModeInfo) -> LinePart {
    match help.mode {
        InputMode::Normal => LinePart::default(),
        InputMode::Locked => LinePart::default(),
        _ => full_shortcut_list_nonstandard_mode(help),
    }
}

fn full_shortcut_list_nonstandard_mode(help: &ModeInfo) -> LinePart {
    let mut line_part = LinePart::default();
    let keys_and_hints = get_keys_and_hints(help);

    for (long, _short, keys) in keys_and_hints.into_iter() {
        line_part.append(&add_shortcut(help, &long, &keys.to_vec(), false, Some(2)));
    }
    line_part
}

#[rustfmt::skip]
fn get_keys_and_hints(mi: &ModeInfo) -> Vec<(String, String, Vec<KeyWithModifier>)> {
    use Action as A;
    use InputMode as IM;
    use Direction as Dir;
    use actions::SearchDirection as SDir;
    use actions::SearchOption as SOpt;

    let mut old_keymap = mi.get_mode_keybinds();
    let s = |string: &str| string.to_string();

    // Find a keybinding to get back to "Normal" input mode. In this case we prefer '\n' over other
    // choices. Do it here before we dedupe the keymap below!
    let base_mode = mi.base_mode;
    let to_basemode_keys = base_mode.map(|b| action_key(&old_keymap, &[to_base_mode(b)])).unwrap_or_else(|| action_key(&old_keymap, &[TO_NORMAL]));
    let to_basemode_key = if to_basemode_keys.contains(&KeyWithModifier::new(BareKey::Enter)) {
        vec![KeyWithModifier::new(BareKey::Enter)]
    } else {
        // Yield `vec![key]` if `to_normal_keys` has at least one key, or an empty vec otherwise.
        to_basemode_keys.into_iter().take(1).collect()
    };

    // Sort and deduplicate the keybindings first. We sort after the `Key`s, and deduplicate by
    // their `Action` vectors. An unstable sort is fine here because if the user maps anything to
    // the same key again, anything will happen...
    old_keymap.sort_unstable_by(|(keya, _), (keyb, _)| keya.partial_cmp(keyb).unwrap());

    let mut known_actions: Vec<Vec<Action>> = vec![];
    let mut km = vec![];
    for (key, acvec) in old_keymap {
        if known_actions.contains(&acvec) {
            // This action is known already
            continue;
        } else {
            known_actions.push(acvec.to_vec());
            km.push((key, acvec));
        }
    }

    if mi.mode == IM::Pane { vec![
        (s("New"), s("New"), single_action_key(&km, &[A::NewPane{direction: None, pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Change Focus"), s("Move"),
            action_key_group(&km, &[&[A::MoveFocus{direction: Dir::Left}], &[A::MoveFocus{direction: Dir::Down}],
                &[A::MoveFocus{direction: Dir::Up}], &[A::MoveFocus{direction: Dir::Right}]])),
        (s("Close"), s("Close"), single_action_key(&km, &[A::CloseFocus, TO_NORMAL])),
        (s("Rename"), s("Rename"),
            single_action_key(&km, &[A::SwitchToMode{input_mode: IM::RenamePane}, A::PaneNameInput{input: vec![0]}])),
        (s("Toggle Fullscreen"), s("Fullscreen"), single_action_key(&km, &[A::ToggleFocusFullscreen, TO_NORMAL])),
        (s("Toggle Floating"), s("Floating"),
            single_action_key(&km, &[A::ToggleFloatingPanes, TO_NORMAL])),
        (s("Toggle Embed"), s("Embed"), single_action_key(&km, &[A::TogglePaneEmbedOrFloating, TO_NORMAL])),
        (s("Split Right"), s("Right"), single_action_key(&km, &[A::NewPane{direction: Some(Direction::Right), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Split Down"), s("Down"), single_action_key(&km, &[A::NewPane{direction: Some(Direction::Down), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Stack"), s("Stack"), single_action_key(&km, &[A::NewStackedPane{command: None, pane_name: None, near_current_pane: false, tab_id: None}, TO_NORMAL])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Tab {
        // With the default bindings, "Move focus" for tabs is tricky: It binds all the arrow keys
        // to moving tabs focus (left/up go left, right/down go right). Since we sort the keys
        // above and then dedpulicate based on the actions, we will end up with LeftArrow for
        // "left" and DownArrow for "right". What we really expect is to see LeftArrow and
        // RightArrow.
        // FIXME: So for lack of a better idea we just check this case manually here.
        let old_keymap = mi.get_mode_keybinds();
        let focus_keys_full: Vec<KeyWithModifier> = action_key_group(&old_keymap,
            &[&[A::GoToPreviousTab], &[A::GoToNextTab]]);
        let focus_keys = if focus_keys_full.contains(&KeyWithModifier::new(BareKey::Left))
            && focus_keys_full.contains(&KeyWithModifier::new(BareKey::Right)) {
            vec![KeyWithModifier::new(BareKey::Left), KeyWithModifier::new(BareKey::Right)]
        } else {
            action_key_group(&km, &[&[A::GoToPreviousTab], &[A::GoToNextTab]])
        };

        vec![
        (s("New"), s("New"), single_action_key(&km, &[A::NewTab{
            tiled_layout: None,
            floating_layouts: vec![],
            swap_tiled_layouts: None,
            swap_floating_layouts: None,
            tab_name: None,
            should_change_focus_to_new_tab: true,
            cwd: None,
            initial_panes: None,
            first_pane_unblock_condition: None,
        }, TO_NORMAL])),
        (s("Change focus"), s("Move"), focus_keys),
        (s("Close"), s("Close"), single_action_key(&km, &[A::CloseTab, TO_NORMAL])),
        (s("Rename"), s("Rename"),
            single_action_key(&km, &[A::SwitchToMode{input_mode: IM::RenameTab}, A::TabNameInput{input: vec![0]}])),
        (s("Sync"), s("Sync"), single_action_key(&km, &[A::ToggleActiveSyncTab, TO_NORMAL])),
        (s("Break pane to new tab"), s("Break out"), single_action_key(&km, &[A::BreakPane, TO_NORMAL])),
        (s("Break pane left/right"), s("Break"), action_key_group(&km, &[
            &[Action::BreakPaneLeft, TO_NORMAL],
            &[Action::BreakPaneRight, TO_NORMAL],
        ])),
        (s("Toggle"), s("Toggle"), single_action_key(&km, &[A::ToggleTab])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Resize { vec![
        (s("Increase/Decrease size"), s("Increase/Decrease"),
            action_key_group(&km, &[
                &[A::Resize{resize: Resize::Increase, direction: None}],
                &[A::Resize{resize: Resize::Decrease, direction: None}]
            ])),
        (s("Increase to"), s("Increase"), action_key_group(&km, &[
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Left)}],
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Down)}],
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Up)}],
            &[A::Resize{resize: Resize::Increase, direction: Some(Dir::Right)}]
            ])),
        (s("Decrease from"), s("Decrease"), action_key_group(&km, &[
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Left)}],
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Down)}],
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Up)}],
            &[A::Resize{resize: Resize::Decrease, direction: Some(Dir::Right)}]
            ])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Move { vec![
        (s("Switch Location"), s("Move"), action_key_group(&km, &[
            &[Action::MovePane{direction: Some(Dir::Left)}], &[Action::MovePane{direction: Some(Dir::Down)}],
            &[Action::MovePane{direction: Some(Dir::Up)}], &[Action::MovePane{direction: Some(Dir::Right)}]])),
        (s("When done"), s("Back"), to_basemode_key),
    ]} else if mi.mode == IM::Scroll { vec![
        (s("Enter search term"), s("Search"),
            action_key(&km, &[A::SwitchToMode{input_mode: IM::EnterSearch}, A::SearchInput{input: vec![0]}])),
        (s("Scroll"), s("Scroll"),
            action_key_group(&km, &[&[Action::ScrollDown], &[Action::ScrollUp]])),
        (s("Scroll page"), s("Scroll"),
            action_key_group(&km, &[&[Action::PageScrollDown], &[Action::PageScrollUp]])),
        (s("Scroll half page"), s("Scroll"),
            action_key_group(&km, &[&[Action::HalfPageScrollDown], &[Action::HalfPageScrollUp]])),
        (s("Edit scrollback in default editor"), s("Edit"),
            single_action_key(&km, &[Action::EditScrollback { ansi: false }, TO_NORMAL])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::EnterSearch { vec![
        (s("When done"), s("Done"), action_key(&km, &[A::SwitchToMode{input_mode: IM::Search}])),
        (s("Cancel"), s("Cancel"),
            action_key(&km, &[A::SearchInput{input: vec![27]}, A::SwitchToMode{input_mode: IM::Scroll}])),
    ]} else if mi.mode == IM::Search { vec![
        (s("Enter Search term"), s("Search"),
            action_key(&km, &[A::SwitchToMode{input_mode: IM::EnterSearch}, A::SearchInput{input: vec![0]}])),
        (s("Scroll"), s("Scroll"),
            action_key_group(&km, &[&[Action::ScrollDown], &[Action::ScrollUp]])),
        (s("Scroll page"), s("Scroll"),
            action_key_group(&km, &[&[Action::PageScrollDown], &[Action::PageScrollUp]])),
        (s("Scroll half page"), s("Scroll"),
            action_key_group(&km, &[&[Action::HalfPageScrollDown], &[Action::HalfPageScrollUp]])),
        (s("Search down"), s("Down"), action_key(&km, &[A::Search{direction: SDir::Down}])),
        (s("Search up"), s("Up"), action_key(&km, &[A::Search{direction: SDir::Up}])),
        (s("Case sensitive"), s("Case"),
            action_key(&km, &[A::SearchToggleOption{option: SOpt::CaseSensitivity}])),
        (s("Wrap"), s("Wrap"),
            action_key(&km, &[A::SearchToggleOption{option: SOpt::Wrap}])),
        (s("Whole words"), s("Whole"),
            action_key(&km, &[A::SearchToggleOption{option: SOpt::WholeWord}])),
    ]} else if mi.mode == IM::Session { vec![
        (s("Detach"), s("Detach"), action_key(&km, &[Action::Detach])),
        (s("Session Manager"), s("Manager"), session_manager_key(&km)),
        (s("Share"), s("Share"), share_key(&km)),
        (s("Configure"), s("Config"), configuration_key(&km)),
        (s("Layout Manager"), s("Layouts"), layout_manager_key(&km)),
        (s("Plugin Manager"), s("Plugins"), plugin_manager_key(&km)),
        (s("About"), s("About"), about_key(&km)),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if mi.mode == IM::Tmux { vec![
        (s("Move focus"), s("Move"), action_key_group(&km, &[
            &[A::MoveFocus{direction: Dir::Left}], &[A::MoveFocus{direction: Dir::Down}],
            &[A::MoveFocus{direction: Dir::Up}], &[A::MoveFocus{direction: Dir::Right}]])),
        (s("Split down"), s("Down"), action_key(&km, &[A::NewPane{direction: Some(Dir::Down), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Split right"), s("Right"), action_key(&km, &[A::NewPane{direction: Some(Dir::Right), pane_name: None, start_suppressed: false}, TO_NORMAL])),
        (s("Fullscreen"), s("Fullscreen"), action_key(&km, &[A::ToggleFocusFullscreen, TO_NORMAL])),
        (s("New tab"), s("New"), action_key(&km, &[A::NewTab{
            tiled_layout: None,
            floating_layouts: vec![],
            swap_tiled_layouts: None,
            swap_floating_layouts: None,
            tab_name: None,
            should_change_focus_to_new_tab: true,
            cwd: None,
            initial_panes: None,
            first_pane_unblock_condition: None,
        }, TO_NORMAL])),
        (s("Rename tab"), s("Rename"),
            action_key(&km, &[A::SwitchToMode{input_mode: IM::RenameTab}, A::TabNameInput{input: vec![0]}])),
        (s("Previous Tab"), s("Previous"), action_key(&km, &[A::GoToPreviousTab, TO_NORMAL])),
        (s("Next Tab"), s("Next"), action_key(&km, &[A::GoToNextTab, TO_NORMAL])),
        (s("Select pane"), s("Select"), to_basemode_key),
    ]} else if matches!(mi.mode, IM::RenamePane | IM::RenameTab) { vec![
        (s("When done"), s("Done"), to_basemode_key),
    ]} else { vec![] }
}

fn shortened_shortcut_list_nonstandard_mode(help: &ModeInfo) -> LinePart {
    let mut line_part = LinePart::default();
    let keys_and_hints = get_keys_and_hints(help);

    for (_, short, keys) in keys_and_hints.into_iter() {
        line_part.append(&add_shortcut(help, &short, &keys.to_vec(), false, Some(2)));
    }
    line_part
}

fn shortened_shortcut_list(help: &ModeInfo) -> LinePart {
    match help.mode {
        InputMode::Normal => LinePart::default(),
        InputMode::Locked => LinePart::default(),
        _ => shortened_shortcut_list_nonstandard_mode(help),
    }
}

fn best_effort_shortcut_list(help: &ModeInfo, max_len: usize) -> LinePart {
    let mut line_part = LinePart::default();
    let keys_and_hints = get_keys_and_hints(help);
    for (_, short, keys) in keys_and_hints.into_iter() {
        let shortcut = add_shortcut(help, &short, &keys.to_vec(), false, Some(2));
        if line_part.len + shortcut.len + MORE_MSG.chars().count() > max_len {
            line_part.part = format!("{}{}", line_part.part, MORE_MSG);
            line_part.len += MORE_MSG.chars().count();
            break;
        } else {
            line_part.append(&shortcut);
        }
    }
    line_part
}

fn single_action_key(
    keymap: &[(KeyWithModifier, Vec<Action>)],
    action: &[Action],
) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        if acvec.iter().next() == action.iter().next() {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn session_manager_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("session-manager"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn share_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("zellij:share"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn plugin_manager_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("plugin-manager"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn layout_manager_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("zellij:layout-manager"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn about_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("zellij:about"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn configuration_key(keymap: &[(KeyWithModifier, Vec<Action>)]) -> Vec<KeyWithModifier> {
    let mut matching = keymap.iter().find_map(|(key, acvec)| {
        let has_match = acvec
            .iter()
            .find(|a| a.launches_plugin("configuration"))
            .is_some();
        if has_match {
            Some(key.clone())
        } else {
            None
        }
    });
    if let Some(matching) = matching.take() {
        vec![matching]
    } else {
        vec![]
    }
}

fn style_key_with_modifier(keyvec: &[KeyWithModifier], color_index: Option<usize>) -> LinePart {
    if keyvec.is_empty() {
        return LinePart::default();
    }

    let common_modifiers = get_common_modifiers(keyvec.iter().collect());

    let no_common_modifier = common_modifiers.is_empty();
    let modifier_str = common_modifiers
        .iter()
        .map(|m| m.to_string())
        .collect::<Vec<_>>()
        .join("-");

    // Prints the keys
    let key = keyvec
        .iter()
        .map(|key| {
            if no_common_modifier || keyvec.len() == 1 {
                format!("{}", key)
            } else {
                format!("{}", key.strip_common_modifiers(&common_modifiers))
            }
        })
        .collect::<Vec<String>>();

    // Special handling of some pre-defined keygroups
    let key_string = key.join("");
    let key_separator = match &key_string[..] {
        "HJKL" => "",
        "hjkl" => "",
        "←↓↑→" => "",
        "←→" => "",
        "↓↑" => "",
        "[]" => "",
        _ => "|",
    };

    if no_common_modifier || key.len() == 1 {
        let key_string_text = format!(" {} ", key.join(key_separator));
        let text = if let Some(color_index) = color_index {
            Text::new(&key_string_text)
                .color_range(color_index, ..)
                .opaque()
        } else {
            Text::new(&key_string_text).opaque()
        };
        LinePart {
            part: serialize_text(&text),
            len: key_string_text.width(),
        }
    } else {
        let key_string_without_modifier = format!("{}", key.join(key_separator));
        let key_string_text = format!(" {} <{}> ", modifier_str, key_string_without_modifier);
        let text = if let Some(color_index) = color_index {
            Text::new(&key_string_text)
                .color_range(color_index, ..modifier_str.width() + 1)
                .color_range(
                    color_index,
                    modifier_str.width() + 3
                        ..modifier_str.width() + 3 + key_string_without_modifier.width(),
                )
                .opaque()
        } else {
            Text::new(&key_string_text).opaque()
        };
        LinePart {
            part: serialize_text(&text),
            len: key_string_text.width(),
        }
    }
}

fn get_common_modifiers(mut keyvec: Vec<&KeyWithModifier>) -> Vec<KeyModifier> {
    if keyvec.is_empty() {
        return vec![];
    }
    let mut common_modifiers = keyvec.pop().unwrap().key_modifiers.clone();
    for key in keyvec {
        common_modifiers = common_modifiers
            .intersection(&key.key_modifiers)
            .cloned()
            .collect();
    }
    common_modifiers.into_iter().collect()
}
