<div align="center">

# 🏠 nebelhaus

**an opinionated macOS, raised in the fog**

silver-grey · keyboard-first · reproducible · nix-native

<!-- assets/hero.png — the whole desktop: Sill bar, Prowl tiling, Pounce open, Nebelung everywhere -->
![nebelhaus](./assets/hero.png)

</div>

---

macOS, arranged like a tiling Linux rig but native to the grain of the Mac —
one Nix flake raises the whole house. Fog-grey, quiet, and reproducible: wipe
the machine, run one command, and the house stands again exactly as it was.

Think *omarchy*, but for macOS instead of Arch.

## the rooms

The house is built from composable nix-darwin modules. Take the whole thing, or
import one room into your own config.

| room | what it does |
|------|--------------|
| 🛖 **den** | the foundation — macOS defaults (dock/finder/trackpad/keyboard), the Homebrew framework + tap-trust, core CLI tools, fonts, weekly GC |
| 🐈 **prowl** | opinionated [AeroSpace](https://github.com/nikitabobko/AeroSpace) tiling, launched via launchd (survives cold boot), Caps→F18 leader, wake-time window re-sort |
| 🪟 **sill** | a [SketchyBar](https://github.com/FelixKratz/SketchyBar) setup perched on the top edge, with stray-agent eviction |
| 🔥 **hearth** | the terminal experience — zsh, a Nebelung-tinted starship prompt, git, and a themed toolbelt (bat, delta, lazygit, lsd, yazi, zoxide, fzf), plus the ghostty / zellij / yazi dotfiles |
| 🔖 **collar** | identity & auth — Touch ID for sudo (with `reattach`, so it works inside tmux/zellij) |
| 🐾 **pounce** | the [Pounce](https://github.com/nebelhaus/pounce) command palette, wired in as a self-signing daemon that holds its Accessibility grant across rebuilds, and ⌘Space freed for it |

Plus the theme, [**nebelung**](https://github.com/nebelhaus/nebelung) — a
silver-mist Catppuccin variant — and [**pounce**](https://github.com/nebelhaus/pounce),
both consumed as flake inputs.

## raise the whole house

```sh
curl -fsSL https://raw.githubusercontent.com/nebelhaus/nebelhaus/main/bootstrap.sh | bash
```

It installs the prerequisites (Xcode CLT, Determinate Nix), clones the repo, and
hands you the exact rebuild command scoped to your machine. It won't switch a
config that isn't yours — you personalize a host file first (the bootstrap
scaffolds one from `hosts/example`).

The rebuild, always build-first:

```sh
nix build .#darwinConfigurations.<hostname>.system \
  && sudo ./result/sw/bin/darwin-rebuild switch --flake .#<hostname>
```

## steal one room

Every room is a `darwinModule`. Pull just what you want into your own flake:

```nix
{
  inputs.nebelhaus.url = "github:nebelhaus/nebelhaus";

  # in your darwinSystem modules list:
  modules = [
    inputs.nebelhaus.darwinModules.prowl   # just the tiling
    inputs.nebelhaus.darwinModules.sill    # just the bar
  ];
}
```

Or lean on the builder for the full rice:

```nix
darwinConfigurations.mymac = inputs.nebelhaus.mkNebelhaus {
  username = "ada";
  hostname = "mymac";
  host = ./hosts/mymac;
};
```

## identity is the only thing that's yours

nebelhaus ships everything — system *and* shell. The only things it leaves blank
are the bits that are personal to you: git name/email/signing key
(`nebelhaus.git.*`), the pounce signing identity, your secrets, and your private
app list. All of those live in your host file (`hosts/<hostname>/default.nix`) —
so the rice is complete out of the box, and you layer *you* on top.

## identity

- **pounce signing** — set `nebelhaus.pounce.signingIdentity` to an Apple
  Development identity's SHA-1 (`security find-identity -v -p codesigning`) so
  the palette's Accessibility grant survives rebuilds. Leave empty to run
  unsigned. See the [pounce README](https://github.com/nebelhaus/pounce) for the
  one-time accessibility approval.
- **git / GPG / YubiKey** — commit signing is configured in your host's
  home-manager block; key material and any smartcard/YubiKey setup live outside
  Nix (gpg-agent + pinentry-mac).

## the fog

Grey is the point. Nebelung is a low-contrast, muted dark palette for people who
find Mocha too loud — a cat breed the colour of high fog, hence the name.

## license

MIT · built on [Nix](https://nixos.org), [nix-darwin](https://github.com/LnL7/nix-darwin),
[home-manager](https://github.com/nix-community/home-manager),
[AeroSpace](https://github.com/nikitabobko/AeroSpace),
[SketchyBar](https://github.com/FelixKratz/SketchyBar), and
[Catppuccin](https://github.com/catppuccin).
