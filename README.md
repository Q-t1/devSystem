## How to use it

# For NixOS (+ Home-Manager) profiles

~~~
sudo nixos-rebuild switch --flake .#<profile>
~~~

Example:

~~~
sudo nixos-rebuild switch --flake .#wsl
~~~

## First switch onto Determinate Nix

Every NixOS profile runs [Determinate Nix](https://determinate.systems), whose
`nix` package comes from the `determinate` flake input rather than nixpkgs, so
it is not in `cache.nixos.org`. On a host that is not yet running
`determinate-nixd`, the daemon doing the build has no Determinate substituter
configured — `nix.settings` only applies *after* activation — so it would
compile Nix (and `sentry-native`) from source. Pass the cache on the command
line for that one bootstrap switch:

~~~
sudo nixos-rebuild switch --flake .#<profile> \
  --option extra-substituters https://install.determinate.systems \
  --option extra-trusted-public-keys cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM=
~~~

Afterwards `determinate-nixd` writes those substituters into `/etc/nix/nix.conf`
itself (the NixOS-generated config moves to `nix.custom.conf`), so subsequent
rebuilds need no flags. Keep the `determinate` input reasonably current
(`nix flake update determinate`): `install.determinate.systems` only carries the
current stable build, and a stale pin falls back to compiling Nix from source.

## homelab-1: microVMs and infrastructure

The microVM host layer, its guests and the services on them live in the
separate [Qt1-Infrastructure](../Qt1-Infrastructure) flake; this flake only
carries OS configuration. homelab-1 imports
`inputs.qt1-infrastructure.nixosModules.default` and turns the pieces on with
`qt1.infra.*` options in `config/profiles/homelab-1/configuration.nix`.

Guests are built, installed and restarted by `nixos-rebuild switch` here, so
deploying an infrastructure change is still a switch of this flake — after
pulling the new revision in:

~~~
nix flake update qt1-infrastructure
sudo nixos-rebuild switch --flake .#homelab-1
~~~

To iterate on both repos at once, without committing to the infra one:

~~~
sudo nixos-rebuild switch --flake .#homelab-1 \
  --override-input qt1-infrastructure path:/Users/quentin/Projects/Qt1-Infrastructure
~~~

Provisioning the Cloudflare tunnel token, adding a guest, and the guest network
layout are documented in that repo's README.

# For standalone Home-Manager profiles (macOS)

Nix on macOS comes from [Determinate Nix](https://determinate.systems) — there
is no NixOS or nix-darwin layer, so the profile is applied with Home Manager
directly:

~~~
nix run home-manager/master -- switch --flake .#macos
~~~

Once `home-manager` is on PATH (the profile installs it), it's just:

~~~
home-manager switch --flake .#macos
~~~

# Build flake (Useful for CI)

~~~
nix build --print-out-paths '.#nixosConfigurations.homelab-1.config.system.build.toplevel' \
  --no-link \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes
~~~

For a standalone Home-Manager profile the attribute is different:

~~~
nix build --print-out-paths '.#homeConfigurations.macos.activationPackage' \
  --no-link \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes
~~~

# Profile matrix

| Host      | System         | Kind  | Home Directory  |
|-----------|----------------|-------|-----------------|
| macos     | aarch64-darwin | home  | /Users/quentin  |
| homelab-1 | x86_64-linux   | nixos | /home/qt1       |
| wsl       | x86_64-linux   | nixos | /home/qt1       |
