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

## homelab-1: cloudflared microVM

homelab-1 runs [microvm.nix](https://github.com/microvm-nix/microvm.nix) guests,
declared in `config/profiles/homelab-1/microvms.nix`. They sit on a NAT'd
bridge (`microvm`, 10.100.0.0/24, host at .1) and are built, installed and
restarted by `nixos-rebuild switch`.

`cloudflared` (10.100.0.2) runs a dashboard-managed Cloudflare Tunnel — the
entrypoint into the local infrastructure. It stays stopped until its tunnel
token is on the host. Create the tunnel in the Cloudflare Zero Trust dashboard
(connector: cloudflared), copy its token, then on homelab-1, after the first
switch:

~~~
sudo install -m 0400 -o microvm -g kvm /dev/stdin /var/lib/microvms/cloudflared/tunnel-token
# paste the token, then Ctrl-D
sudo systemctl start microvm@cloudflared
~~~

The token is only read when the VM boots: after rotating it, run
`sudo systemctl restart microvm@cloudflared`. Tunnel logs are on the host, in
`journalctl -u microvm@cloudflared`.

Routes (public hostnames, private networks) are configured in the dashboard.
LAN origins see the tunnel's traffic coming from 192.168.1.230; a service on
homelab-1 itself also needs its port opened in the host firewall.

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
