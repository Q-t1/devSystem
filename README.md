## How to use it

# For NixOS (+ Home-Manager) profiles

~~~
sudo nixos-rebuild switch --flake .#<profile>
~~~

Example:

~~~
sudo nixos-rebuild switch --flake .#wsl
~~~

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
nix build --print-out-paths '.#nixosConfigurations.infra-t0.config.system.build.toplevel' \
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

| Host     | System         | Kind  | Home Directory  |
|----------|----------------|-------|-----------------|
| macos    | aarch64-darwin | home  | /Users/quentin  |
| infra-t0 | x86_64-linux   | nixos | /home/qt1       |
| infra-t1 | x86_64-linux   | nixos | /home/qt1       |
| wsl      | x86_64-linux   | nixos | /home/qt1       |
