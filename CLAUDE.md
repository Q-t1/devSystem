# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A Nix flake managing NixOS system configurations and Home Manager user configurations across multiple machines. All hosts share `config/common/home.nix` as a base; each host extends it with a profile-specific `home.nix`.

## Commands

Apply a profile (NixOS):
```
sudo nixos-rebuild switch --flake .#<profile>
```

Apply a standalone Home Manager profile (macOS — Nix there is Determinate Nix,
with no NixOS/nix-darwin layer):
```
home-manager switch --flake .#macos
```

Format Nix files:
```
nix fmt
```

Build a profile without activating (useful for CI / syntax checks):
```
nix build --print-out-paths '.#nixosConfigurations.<profile>.config.system.build.toplevel' \
  --no-link \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes
```

For `kind = "home"` profiles the attribute is `homeConfigurations.<profile>.activationPackage`
instead.

## Architecture

### Profile auto-discovery

`flake.nix` reads every subdirectory of `config/profiles/` and imports its `host.nix`. That file declares two fields:

```nix
{ system = "x86_64-linux"; kind = "nixos"; }
```

- `kind = "nixos"` → entry goes into `nixosConfigurations`, combining `configuration.nix` + Home Manager inline
- `kind = "home"` → entry goes into `homeConfigurations` (standalone Home Manager only); no `configuration.nix` is read

Two optional fields override flake-wide defaults (see `config/profiles/macos/host.nix`):

- `username` — defaults to `"qt1"`
- `homeDirectory` — defaults to `/Users/<username>` on a `*-darwin` system, `/home/<username>` otherwise

Adding a new host requires only a new directory with `host.nix`, `home.nix`, and — for `kind = "nixos"` — `configuration.nix`; no edits to `flake.nix`.

### Layer order (NixOS hosts)

1. `config/modules/nix-settings.nix` and `config/modules/claude-code.nix` — always applied globally (nix experimental features; the `claude-code` overlay)
2. `config/profiles/<profile>/configuration.nix` — system-level config; imports hardware, modules, etc.
3. `config/common/home.nix` — shared Home Manager base (zsh, git, neovim, zed, nil/nixd LSPs)
4. `config/profiles/<profile>/home.nix` — profile-specific Home Manager additions

### Layer order (standalone Home hosts — `macos`)

There is no system layer: Determinate Nix owns `/nix` and `/etc/nix/nix.conf`,
so `nix-settings.nix` / `claude-code.nix` (both NixOS modules) do not apply.
`mkHome` in `flake.nix` covers what they would have: it instantiates nixpkgs
with the `claude-code` overlay and `allowUnfree = true`.

1. `config/common/home.nix` — shared Home Manager base
2. `config/profiles/macos/home.nix` — profile-specific additions

Anything the shared base pulls in must therefore evaluate on `aarch64-darwin`;
Linux-only packages need a `lib.optionals pkgs.stdenv.hostPlatform.isLinux`
guard (see `ghostty.terminfo` in `config/common/home.nix`).

### Determinate Nix (NixOS hosts)

`flake.nix` applies `inputs.determinate.nixosModules.default` to every
`kind = "nixos"` profile, so `nix.package` is the `determinate` input's build,
not nixpkgs' — never set `nix.package` in a profile, it conflicts. That package
is served by `https://install.determinate.systems`, not `cache.nixos.org`, and
only the current stable build is kept there, so run
`nix flake update determinate` when the pin ages or the host compiles Nix from
source. A host's *first* switch onto Determinate needs the substituter passed on
the command line (see README) because `nix.settings` only applies after
activation; afterwards `determinate-nixd` owns `/etc/nix/nix.conf` and the
NixOS-generated settings land in `/etc/nix/nix.custom.conf`.

The `macos` profile is `kind = "home"`, so this module does not apply there —
Determinate Nix on that machine comes from the standalone installer.

### Reusable modules (`config/modules/`)

Standalone NixOS modules imported explicitly by profiles that need them:
- `boot-efi.nix` — EFI boot loader
- `locale-fr.nix` — French locale
- `openssh.nix` — SSH daemon
- `user-qt1-server.nix` — user account setup for server hosts
- `nix-settings.nix` — experimental features (always applied via `flake.nix`)
- `claude-code.nix` — overlays `pkgs.claude-code` with the `claude-code` flake
  input (`github:sadjow/claude-code-nix`, hourly upstream releases instead of
  the slower nixpkgs one) and adds its cachix substituter; also always applied
  via `flake.nix`, so every call site keeps using `pkgs.claude-code`

One directory here is a **Home Manager** module, imported from a profile's
`home.nix` rather than its `configuration.nix`:
- `coding-ide/` — the `coding` IDE (yazi + zellij + nixvim). `default.nix` is
  the yazi/zellij workspace, `nvim.nix` the editor. Exposes one option,
  `programs.codingIde.clipboardProvider` (`wsl` | `pbcopy` | `osc52` | `none`),
  so each profile picks how the clipboard is reached — this also gates the
  Linux-only `wl-clipboard` dependency, which only the `wsl` provider pulls in.
  Imported by wsl (`wsl`) and macos (`pbcopy`). Pulls the unfree `claude-code`
  (see `claude-code.nix` above), so an importing NixOS profile needs
  `nixpkgs.config.allowUnfree = true`; `kind = "home"` profiles get it from
  `mkHome`.

### Profile matrix

| Profile   | System         | Kind  | Notes                                      |
|-----------|----------------|-------|--------------------------------------------|
| wsl       | x86_64-linux   | nixos | WSL2, Docker, Zen Browser, bleu rootCA     |
| macos     | aarch64-darwin | home  | Determinate Nix on macOS, user `quentin`; coding-ide |
| homelab-1 | x86_64-linux   | nixos | Bare-metal server, minimal: static IP 192.168.1.230 + DNS + SSH |

### Special args available in all modules

- `inputs` — flake inputs (use for `inputs.zen-browser.homeModules.default`, etc.)
- `username` — `"qt1"`
- `profile` — the profile name string
- `system` — the system string (e.g. `"x86_64-linux"`)
- `kind` — `"nixos"` or `"home"`; used by `coding-ide/nvim.nix` to point nixd at
  the right flake output for option completion
