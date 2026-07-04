# CLAUDE.md

**nebelhaus** — an opinionated macOS rice as composable nix-darwin modules. This
repo is the "distro": a personal machine consumes it via `mkNebelhaus` and adds
only its own host (identity, private apps, secrets).

## Am I in the right repo? (routing)

**This repo (`~/code/nebelhaus/nebelhaus`) owns THE RICE** — the generic, no-identity
system + shell modules. Personal machine config and the pounce/theme sources live
elsewhere.

| Want to change… | Repo |
|---|---|
| the rice: macOS defaults, tiling (prowl), bar (sill), shell (hearth), security (collar), pounce wiring (den) | `~/code/nebelhaus/nebelhaus` ← **you are here** |
| the pounce palette app or its command scripts | `~/code/nebelhaus/pounce` |
| colors / the theme palette | `~/code/nebelhaus/nebelung` |
| one machine's personal apps / identity / secrets | `~/.config/nix` (or that machine's own config) |

> **Claude: enforce this.** If a request targets a different repo than the one
> whose files you're in, STOP and say so before editing — e.g. "That's a color
> change; the palette lives in `~/code/nebelhaus/nebelung`. Want me to switch?"
> Never hardcode a user's identity here — it's a `nebelhaus.*` option the host sets.

## Architecture

```
flake.nix                 # mkNebelhaus builder + darwinModules outputs + example host
modules/
  default.nix             # imports all rooms
  options.nix             # nebelhaus.git.* + nebelhaus.pounce.signingIdentity (host-set)
  lib/gui-wait.nix        # withGUIWait: cold-boot-safe GUI agent launch wrapper
  den/                    # system: macOS defaults, Homebrew framework, core CLI, GC
  hearth/                 # shell: zsh, starship, git, yazi, zellij, ghostty + theming
  prowl/                  # AeroSpace tiling
  sill/                   # SketchyBar
  collar/                 # Touch ID sudo
  pounce/                 # the palette daemon (launchd + self-signing)
hosts/example/            # the template a consumer copies
```

Each `modules/<room>` is a nix-darwin module; ones that need home config write into
`home-manager.users.${username}`. `den` and `hearth` split system vs shell; Homebrew
is contributed per-room (den owns the framework, prowl/sill add their own cask/brew).

## Build / test

It's a library, so there's no local machine to switch. Verify it **evaluates**:

```bash
nix eval .#darwinConfigurations.example.system.drvPath
```

The `example` host uses placeholder identity (user `you`), so a full build isn't
meaningful — real testing happens in a consumer (e.g. `~/.config/nix`, host `mbp`).
After a change here, the consumer runs `nix flake update nebelhaus` + rebuild.

## Rules

- **Never hardcode identity.** Anything personal (git name/email/signing key, the
  pounce signing cert) is a `nebelhaus.*` option set by the host — see `options.nix`.
- A **dynamic attr key** (`${username}`) can't be defined across multiple statements —
  set `home-manager.users.${username}` once per module. Pass it as a module *function*
  (`{ lib, pkgs, ... }: {...}`) when you need home-manager's `lib.hm`.
- `nixfmt` formats `.nix` files.

## Gotchas

- **launchd GUI race**: GUI agents (AeroSpace, SketchyBar, pounce) launched at cold
  boot before the Aqua session is ready park with exit 78 (EX_CONFIG) and wedge.
  `withGUIWait` (`modules/lib/gui-wait.nix`) polls for Dock/Finder/SystemUIServer and
  runs from `/bin/bash` (boot volume, not the /nix APFS volume that isn't mounted yet).
  Don't "simplify" it away. Recover a wedged agent: `launchctl bootout` then `bootstrap`.
- **pounce self-signing** (`modules/pounce`): macOS keys an Accessibility (TCC) grant
  to a code-signing identity, but a store build is adhoc-signed (cdhash changes every
  rebuild). When `nebelhaus.pounce.signingIdentity` is set, the daemon wrapper copies
  `Pounce.app` to `~/.local/state/pounce` and re-signs it with a stable identity so the
  grant survives rebuilds. Don't repoint the agent at the store path. One-time on a new
  machine: `pounce --request-accessibility`, approve the prompt (and the keychain
  "Always Allow" dialog the first time `codesign` runs).
- **Homebrew tap-trust** (`modules/den`): `HOMEBREW_NO_REQUIRE_TAP_TRUST=1` via
  `/etc/homebrew/brew.env` — third-party taps fail trust checks under sudo activation.
- **Touch ID + zellij** (`modules/collar`): `reattach = true` is required because sudo
  runs inside zellij; without pam_reattach the Touch ID prompt beachballs.
- **Determinate owns the nix daemon** (`modules/den`): `nix.enable = false`; config
  lives in `/etc/nix/nix.custom.conf`. GC is our own weekly launchd job.
- **The pounce build shells out to `/usr/bin/xcrun swiftc`** — needs Xcode CLT + the
  macOS build sandbox relaxed (Determinate's default). See the pounce repo.

## Patterns

- **New SketchyBar plugin**: add `modules/sill/sketchybar/plugins/<name>.sh`, wire it
  into `modules/sill/sketchybar/sketchybarrc`. Follow an existing plugin.
- **Theme**: `catppuccin.flavor` (in `hearth`) is the single source of truth; the
  Nebelung palette is injected from the `nebelung` input. Raw dotfiles nix can't inject
  into (ghostty `config`, zellij `config.kdl`) name the flavor manually — keep in sync.
- **New pounce command**: generic ones live in the
  [pounce repo](https://github.com/nebelhaus/pounce) (`pkgs/pounce-commands/commands`);
  rice/machine-specific ones live HERE in `modules/pounce/commands/` — one
  self-describing script each (metadata in a `# pounce: key = value` header),
  layered onto the palette via `pounce-commands.override { extraCommandDirs … }`.
  No registry to edit in either repo; drop the script and rebuild.
```
