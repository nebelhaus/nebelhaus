use ansi_term::ANSIStrings;
use unicode_width::UnicodeWidthStr;

use crate::{LinePart, ARROW_SEPARATOR};
use zellij_tile::prelude::actions::Action;
use zellij_tile::prelude::*;
use zellij_tile_utils::style;

fn get_current_title_len(current_title: &[LinePart]) -> usize {
    current_title.iter().map(|p| p.len).sum()
}

// move elements from before_active and after_active into tabs_to_render while they fit in cols
// adds collapsed_tabs to the left and right if there's left over tabs that don't fit
//
// Fork note: this is upstream zellij tab-bar's viewport logic, kept VERBATIM —
// it is the whole reason this plugin exists. It keeps the active tab visible and
// roughly centred, spilling the overflow into `← +N` / `+N →` collapsed-count
// pills on either side (a deterministic function of the active index + tab
// widths, so it reflows to one canonical form). zjstatus had no equivalent, so
// tabs there just ran under the right-hand widgets and clipped mid-ribbon.
fn populate_tabs_in_tab_line(
    tabs_before_active: &mut Vec<LinePart>,
    tabs_after_active: &mut Vec<LinePart>,
    tabs_to_render: &mut Vec<LinePart>,
    cols: usize,
    palette: Styling,
    capabilities: PluginCapabilities,
) {
    let mut middle_size = get_current_title_len(tabs_to_render);

    let mut total_left = 0;
    let mut total_right = 0;
    loop {
        let left_count = tabs_before_active.len();
        let right_count = tabs_after_active.len();

        // left_more_tab_index is first tab to the left of the leftmost visible tab
        let left_more_tab_index = left_count.saturating_sub(1);
        let collapsed_left = left_more_message(
            left_count,
            palette,
            tab_separator(capabilities),
            left_more_tab_index,
        );

        // right_more_tab_index is the first tab to the right of the rightmost visible tab
        let right_more_tab_index = left_count + tabs_to_render.len();
        let collapsed_right = right_more_message(
            right_count,
            palette,
            tab_separator(capabilities),
            right_more_tab_index,
        );

        let total_size = collapsed_left.len + middle_size + collapsed_right.len;

        if total_size > cols {
            // break and dont add collapsed tabs to tabs_to_render, they will not fit
            break;
        }

        let left = if let Some(tab) = tabs_before_active.last() {
            tab.len
        } else {
            usize::MAX
        };

        let right = if let Some(tab) = tabs_after_active.first() {
            tab.len
        } else {
            usize::MAX
        };

        // total size is shortened if the next tab to be added is the last one, as that will remove the collapsed tab
        let size_by_adding_left =
            left.saturating_add(total_size)
                .saturating_sub(if left_count == 1 {
                    collapsed_left.len
                } else {
                    0
                });
        let size_by_adding_right =
            right
                .saturating_add(total_size)
                .saturating_sub(if right_count == 1 {
                    collapsed_right.len
                } else {
                    0
                });

        let left_fits = size_by_adding_left <= cols;
        let right_fits = size_by_adding_right <= cols;
        // active tab is kept in the middle by adding to the side that
        // has less width, or if the tab on the other side doesn't fit
        if (total_left <= total_right || !right_fits) && left_fits {
            // add left tab
            let tab = tabs_before_active.pop().unwrap();
            middle_size += tab.len;
            total_left += tab.len;
            tabs_to_render.insert(0, tab);
        } else if right_fits {
            // add right tab
            let tab = tabs_after_active.remove(0);
            middle_size += tab.len;
            total_right += tab.len;
            tabs_to_render.push(tab);
        } else {
            // there's either no space to add more tabs or no more tabs to add, so we're done
            tabs_to_render.insert(0, collapsed_left);
            tabs_to_render.push(collapsed_right);
            break;
        }
    }
}

fn left_more_message(
    tab_count_to_the_left: usize,
    palette: Styling,
    separator: &str,
    tab_index: usize,
) -> LinePart {
    if tab_count_to_the_left == 0 {
        return LinePart::default();
    }
    let more_text = if tab_count_to_the_left < 10000 {
        format!(" ← +{} ", tab_count_to_the_left)
    } else {
        " ← +many ".to_string()
    };
    // 238
    // chars length plus separator length on both sides
    let more_text_len = more_text.width() + 2 * separator.width();
    let (text_color, sep_color) = (
        palette.ribbon_unselected.base,
        palette.text_unselected.background,
    );
    let left_separator = style!(sep_color, palette.ribbon_unselected.background).paint(separator);
    let more_styled_text = style!(text_color, palette.ribbon_unselected.background)
        .bold()
        .paint(more_text);
    let right_separator = style!(palette.ribbon_unselected.background, sep_color).paint(separator);
    let more_styled_text =
        ANSIStrings(&[left_separator, more_styled_text, right_separator]).to_string();
    LinePart {
        part: more_styled_text,
        len: more_text_len,
        tab_index: Some(tab_index),
    }
}

fn right_more_message(
    tab_count_to_the_right: usize,
    palette: Styling,
    separator: &str,
    tab_index: usize,
) -> LinePart {
    if tab_count_to_the_right == 0 {
        return LinePart::default();
    };
    let more_text = if tab_count_to_the_right < 10000 {
        format!(" +{} → ", tab_count_to_the_right)
    } else {
        " +many → ".to_string()
    };
    // chars length plus separator length on both sides
    let more_text_len = more_text.width() + 2 * separator.width();
    let (text_color, sep_color) = (
        palette.ribbon_unselected.base,
        palette.text_unselected.background,
    );
    let left_separator = style!(sep_color, palette.ribbon_unselected.background).paint(separator);
    let more_styled_text = style!(text_color, palette.ribbon_unselected.background)
        .bold()
        .paint(more_text);
    let right_separator = style!(palette.ribbon_unselected.background, sep_color).paint(separator);
    let more_styled_text =
        ANSIStrings(&[left_separator, more_styled_text, right_separator]).to_string();
    LinePart {
        part: more_styled_text,
        len: more_text_len,
        tab_index: Some(tab_index),
    }
}

// Fork: upstream renders a " Zellij (session) " prefix. We show the truncated
// username instead (the old zjstatus `format_left` did the same), as a peach
// powerline pill matching the theme's accent, cut off with a right arrow.
fn tab_line_prefix(
    username: &str,
    palette: Styling,
    capabilities: PluginCapabilities,
    cols: usize,
) -> Vec<LinePart> {
    if username.is_empty() {
        return vec![];
    }
    let separator = tab_separator(capabilities);
    let dark = palette.text_unselected.background;
    let peach = palette.text_unselected.emphasis_0;
    let line_bg = palette.text_unselected.background;
    let text = format!(" {} ", username);
    let len = text.width() + separator.width();
    if len > cols {
        return vec![];
    }
    let pill = style!(dark, peach).bold().paint(text.clone());
    let arrow = style!(peach, line_bg).paint(separator);
    vec![LinePart {
        part: ANSIStrings(&[pill, arrow]).to_string(),
        len,
        tab_index: None,
    }]
}

// Fork: the dim "Ctrl+Tab" reminder the old zjstatus `format_right` carried —
// the built-in bar has no slot for it, which is the whole reason zjstatus was
// adopted. Rendered ourselves so we can drop the third-party dependency.
fn ctrl_tab_reminder(palette: Styling) -> LinePart {
    let text = " Ctrl+Tab ".to_string();
    let fg = palette.ribbon_unselected.background; // dim grey, like the old overlay0
    let bg = palette.text_unselected.background;
    LinePart {
        part: style!(fg, bg).bold().paint(text.clone()).to_string(),
        len: text.width(),
        tab_index: None,
    }
}

pub fn tab_separator(capabilities: PluginCapabilities) -> &'static str {
    if !capabilities.arrow_fonts {
        ARROW_SEPARATOR
    } else {
        ""
    }
}

pub fn tab_line(
    username: &str,
    mut all_tabs: Vec<LinePart>,
    active_tab_index: usize,
    cols: usize,
    palette: Styling,
    capabilities: PluginCapabilities,
    tab_info: Option<&TabInfo>,
    mode_info: &ModeInfo,
    hide_swap_layout_indicator: bool,
    background: &PaletteColor,
) -> Vec<LinePart> {
    let mut tabs_after_active = all_tabs.split_off(active_tab_index);
    let mut tabs_before_active = all_tabs;
    let active_tab = if !tabs_after_active.is_empty() {
        tabs_after_active.remove(0)
    } else {
        tabs_before_active.pop().unwrap()
    };
    let supports_arrow_fonts = !capabilities.arrow_fonts;

    let mut prefix = tab_line_prefix(username, palette, capabilities, cols);
    let mut prefix_len = get_current_title_len(&prefix);

    // Right-side widgets: the Ctrl+Tab reminder, then the swap-layout indicator
    // (Alt <[]> keys + the active layout ribbon). Same order the old zjstatus
    // `format_right` used.
    let mut reminder = Some(ctrl_tab_reminder(palette));
    let mut swap_layout_indicator = if hide_swap_layout_indicator {
        None
    } else {
        tab_info.and_then(|tab_info| {
            swap_layout_status(
                &tab_info.active_swap_layout_name,
                tab_info.is_swap_layout_dirty,
                mode_info,
                supports_arrow_fonts,
            )
        })
    };

    // Reserve space for the right side, shedding it by priority when the pane is
    // too thin: swap ribbon goes first, then the reminder, then (last resort) the
    // username prefix — the active tab is NEVER dropped, so you always know where
    // you are. This is what stops the "tabs run under the widgets and clip" bug.
    loop {
        let right_len = reminder.as_ref().map(|p| p.len).unwrap_or(0)
            + swap_layout_indicator.as_ref().map(|p| p.len).unwrap_or(0);
        if prefix_len + active_tab.len + right_len <= cols {
            break;
        }
        if swap_layout_indicator.is_some() {
            swap_layout_indicator = None;
        } else if reminder.is_some() {
            reminder = None;
        } else if prefix_len > 0 {
            prefix = vec![];
            prefix_len = 0;
        } else {
            break;
        }
    }

    let right_len = reminder.as_ref().map(|p| p.len).unwrap_or(0)
        + swap_layout_indicator.as_ref().map(|p| p.len).unwrap_or(0);
    let non_tab_len = prefix_len + right_len;

    let mut tabs_to_render = vec![active_tab];

    populate_tabs_in_tab_line(
        &mut tabs_before_active,
        &mut tabs_after_active,
        &mut tabs_to_render,
        cols.saturating_sub(non_tab_len),
        palette,
        capabilities,
    );
    prefix.append(&mut tabs_to_render);
    prefix.append(&mut vec![LinePart {
        part: match background {
            PaletteColor::Rgb((r, g, b)) => format!("\u{1b}[48;2;{};{};{}m\u{1b}[0K", r, g, b),
            PaletteColor::EightBit(color) => format!("\u{1b}[48;5;{}m\u{1b}[0K", color),
        },
        len: 0,
        tab_index: None,
    }]);

    if reminder.is_some() || swap_layout_indicator.is_some() {
        let used: usize = prefix.iter().map(|p| p.len).sum();
        let remaining_space = cols.saturating_sub(used).saturating_sub(right_len);
        let mut padding = String::new();
        for _ in 0..remaining_space {
            padding.push_str(
                &style!(
                    palette.text_unselected.background,
                    palette.text_unselected.background
                )
                .paint(" ")
                .to_string(),
            );
        }
        prefix.push(LinePart {
            part: padding,
            len: remaining_space,
            tab_index: None,
        });
        if let Some(reminder) = reminder.take() {
            prefix.push(reminder);
        }
        if let Some(swap_layout_indicator) = swap_layout_indicator.take() {
            prefix.push(swap_layout_indicator);
        }
    }

    prefix
}

fn swap_layout_status(
    swap_layout_name: &Option<String>,
    is_swap_layout_dirty: bool,
    mode_info: &ModeInfo,
    supports_arrow_fonts: bool,
) -> Option<LinePart> {
    match swap_layout_name {
        Some(swap_layout_name) => {
            let mode_keybinds = mode_info.get_mode_keybinds();
            let prev_next_keys = action_key_group(
                &mode_keybinds,
                &[&[Action::PreviousSwapLayout], &[Action::NextSwapLayout]],
            );
            let mut text = style_key_with_modifier(&prev_next_keys, Some(0));
            text.append(&ribbon_as_line_part(
                &swap_layout_name.to_uppercase(),
                !is_swap_layout_dirty,
                supports_arrow_fonts,
            ));
            Some(text)
        },
        None => None,
    }
}

pub fn ribbon_as_line_part(text: &str, is_selected: bool, supports_arrow_fonts: bool) -> LinePart {
    let ribbon_text = if is_selected {
        Text::new(text).selected()
    } else {
        Text::new(text)
    };
    let part = serialize_ribbon(&ribbon_text);
    let mut len = text.width() + 2;
    if supports_arrow_fonts {
        len += 2;
    };
    LinePart {
        part,
        len,
        tab_index: None,
    }
}

pub fn style_key_with_modifier(keyvec: &[KeyWithModifier], color_index: Option<usize>) -> LinePart {
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
            ..Default::default()
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
            ..Default::default()
        }
    }
}

pub fn get_common_modifiers(mut keyvec: Vec<&KeyWithModifier>) -> Vec<KeyModifier> {
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

pub fn action_key_group(
    keymap: &[(KeyWithModifier, Vec<Action>)],
    actions: &[&[Action]],
) -> Vec<KeyWithModifier> {
    let mut ret = vec![];
    for action in actions {
        ret.extend(action_key(keymap, action));
    }
    ret
}

pub fn action_key(
    keymap: &[(KeyWithModifier, Vec<Action>)],
    action: &[Action],
) -> Vec<KeyWithModifier> {
    keymap
        .iter()
        .filter_map(|(key, acvec)| {
            let matching = acvec
                .iter()
                .zip(action)
                .filter(|(a, b)| a.shallow_eq(b))
                .count();

            if matching == acvec.len() && matching == action.len() {
                Some(key.clone())
            } else {
                None
            }
        })
        .collect::<Vec<KeyWithModifier>>()
}
