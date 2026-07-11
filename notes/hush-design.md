# hush — Focus/DND as a room (design brainstorm)

> Status: proposal, not implemented. One toggle in the bar + palette that
> silences notifications (real macOS Focus, so it syncs to your iPhone) and
> sets your Slack status. Declarative where macOS allows; honest where it
> doesn't.

## Shape

`modules/hush/` becomes the seventh room. Like the other rooms it is one
concern with several surfaces, all driven by a single engine:

```
hush (CLI engine, ~/.local/bin)      the state machine: on / off / toggle / status / doctor
├── sill pill                        bell icon, accent-filled when hushed, click = toggle
├── pounce command                   "Toggle Hush" in the palette
└── hooks                            slack (built in) + host-provided scripts, run with "on"/"off"
```

Everything calls the same `hush` script, so the bar, the palette, and the
terminal can never disagree about what a toggle does.

## The hard part: flipping Focus programmatically

Apple ships no public API or CLI to set a Focus. The realistic mechanisms:

| Mechanism | Verdict |
|---|---|
| `shortcuts run <name>` against a user-created Shortcut with a "Set Focus" action | **Chosen.** Apple-supported, survives OS updates, zero TCC prompts, works for any named Focus. Cost: the Shortcut itself can't be created declaratively (imports require signing + a GUI confirmation), so it's a one-time manual step. |
| Symbolic hotkey (`com.apple.symbolichotkeys`) + synthesized keypress | Fully declarative, but the keystroke sender needs an Accessibility grant (sketchybar-spawned scripts attribute to sketchybar), it only reaches classic DND, and key synthesis is layout-fragile. Fallback at best; not v1. |
| UI-scripting Control Center via System Events | Breaks every macOS release. No. |
| Third-party CLIs on private frameworks (do-not-disturb-cli etc.) | Dead since Monterey's Focus rewrite / constant private-API churn. No. |

Why real Focus instead of faking notification silence: **Share Across
Devices** means the iPhone hushes too, and the "allowed to break through"
list is the user's own Focus config — hush flips the switch, it doesn't
reinvent the switchboard.

Two tiny Shortcuts, created once (guided by `hush doctor` and the bootstrap
interview):

- **`hush-toggle`** — "Set Focus: turn <focus> On/Off (toggle)"
- **`hush-status`** — "Get Current Focus → output" (lets `shortcuts run
  hush-status` print the active Focus to stdout)

## Detecting state (keeping the pill truthful)

The user can also toggle Focus from Control Center or their phone, so hush
can't just trust its own last write. Options considered:

1. **Poll `shortcuts run hush-status`** — exact, zero TCC. ~0.5–1 s per
   invocation, fine at a 30 s `update_freq` (the weather pill already curls
   an API on a similar cadence). **Chosen for v1.**
2. Read `~/Library/DoNotDisturb/DB/Assertions.json` — the canonical store,
   instant, and a launchd `WatchPaths` agent on that directory could
   `sketchybar --trigger hush_change` for real-time sync. But the reading
   process needs **Full Disk Access** (sketchybar would need the scariest
   TCC grant we'd ever ask for). Optional v2 enhancement, never required.
3. hush's own state file only — zero cost but drifts the moment the user
   toggles Focus anywhere else. Rejected as primary; still written (see
   timer below).

Instant feedback on our own toggles regardless: the engine fires
`sketchybar --trigger hush_change` after acting, so the pill never waits
for the poll when *we* changed the state.

## The Slack leg

macOS Focus already suppresses Slack banners *on the Mac*. The API leg is
what Focus can't do: tell your **teammates** and silence your **phone**.

- `users.profile.set` → status text + emoji (+ `status_expiration`)
- `dnd.setSnooze` / `dnd.endSnooze` → pauses Slack push on all devices
- Scopes: `users.profile:write`, `dnd:write` on a personal user token
  (one-time: create a tiny personal Slack app, install to workspace)

The token is identity, so per the house rule it never enters the rice: a
`tokenCommand` option the host sets, Keychain-first
(`security find-generic-password -s hush-slack -w`). Same spirit as the
harvest pill's secrets file, but command-shaped so nothing secret ever
touches disk in plaintext.

Slack is implemented as the first built-in **hook** — the extension point
is generic:

```
nebelhaus.hush.hooks = [ ./my-hush-hooks/onair-light.sh ];
# each script is called with "on" or "off"
```

Hook ideas that stay host-side (not shipped): pause Music, turn an Elgato
light red, start a Harvest "deep work" timer, shove distracting apps to a
parking workspace via aerospace.

## Options sketch

```nix
nebelhaus.hush = {
  enable = true;                      # room flag, default on like prowl/sill/pounce
  focus = "Do Not Disturb";           # which Focus the Shortcuts flip; a custom
                                      # named Focus ("Hush") keeps your personal
                                      # DND allowlist separate — recommended in docs
  slack = {
    enable = false;                   # off by default: needs a token
    tokenCommand = "";                # e.g. "security find-generic-password -s hush-slack -w"
    status = { text = "heads down"; emoji = ":no_bell:"; };
    snooze = true;                    # also dnd.setSnooze while hushed
  };
  hooks = [ ];                        # extra scripts, called with "on"/"off"
};
```

## Surfaces, concretely

- **CLI**: `hush` via `pkgs.writeShellApplication` into home packages.
  Subcommands `on|off|toggle|status|doctor`. `doctor` checks the two
  Shortcuts exist (`shortcuts list`), the Slack token resolves, and prints
  the one-time setup steps for whatever is missing.
- **sill**: `modules/sill/sketchybar/plugins/hush.sh` following the elgato
  pattern (icon 󰂚 / 󰂛, `background.color=$ACCENT` when hushed,
  `label.drawing=off`), subscribed to `mouse.clicked` + custom event
  `hush_change`, `update_freq=30`. Emitted into the bar only when
  `hush.enable` — but unlike elgato/harvest it is *not* behind
  `sill.plugins`, because it targets no personal hardware/service. If the
  Shortcuts are missing, a click surfaces "run `hush doctor`" as a
  notification instead of failing silently.
- **pounce**: `modules/pounce/commands/hush.sh` with the usual
  `# pounce:` header ("Toggle Hush", icon `moon.fill`), filtered out of
  `riceCommands` when the room is off.

## v2 candidates (explicitly not v1)

- **Timed hush**: `hush 25` writes an until-timestamp to
  `~/.local/state/hush/`; the poll auto-offs past expiry and the pill label
  shows minutes remaining. Palette grows "Hush 25m / 60m" commands.
- **Assertions.json watcher** for instant external-toggle sync (opt-in,
  costs sketchybar a Full Disk Access grant).
- A prowl leader/binding for hush.

## What hush honestly won't do

- **No declarative Focus allowlists.** Which apps/people break through
  lives in `~/Library/DoNotDisturb/DB/ModeConfigurations.json`, which is
  CloudKit-synced and unsupported to write. Curate it once in System
  Settings; hush only flips the switch. (Scope-honesty in the option
  description, same voice as `theme.accent`.)
- **No declarative Shortcut creation.** Two one-time manual Shortcuts,
  guided by `hush doctor` + the bootstrap interview.
- **No Slack app provisioning.** Token creation is a documented one-time
  walkthrough (workshop repo).

## Downstream

A new "Hush" guide in the workshop repo (`web/src/content/docs/`): the two
Shortcuts, the optional custom "Hush" Focus, the Slack app + Keychain
steps. Per CLAUDE.md this ships alongside the implementation or it drifts.

## Open decisions

1. Default `focus`: plain "Do Not Disturb" vs documenting a custom "Hush"
   Focus as the recommended setup (leaning: default DND so it works with
   zero Focus config, docs recommend the named one).
2. Should `slack.snooze` and status be independently toggleable, or is one
   `slack.enable` enough for v1? (leaning: one flag, both on.)
3. Pill position on the right side (next to wifi? next to media?).
4. Is a timed hush wanted badly enough to pull into v1?
