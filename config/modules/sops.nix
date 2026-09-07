# sops-nix: encrypted secrets committed to this repo, decrypted at activation
# into /run/secrets (tmpfs, never written to the Nix store).
#
# Applied globally from flake.nix, like nix-settings.nix and claude-code.nix,
# so every profile gets the tooling and the same decryption identity.
#
# Per-host workflow:
#   1. rebuild once — this module generates /var/lib/sops-nix/key.txt
#   2. `sudo age-keygen -y /var/lib/sops-nix/key.txt` prints the host's public
#      key; add it to .sops.yaml under `keys:` and to the profile's creation rule
#   3. `sops config/profiles/<profile>/secrets.yaml` to create/edit secrets
#   4. declare each one with `sops.secrets.<name> = { };` in the profile
{
  inputs,
  config,
  lib,
  pkgs,
  profile,
  ...
}:

let
  profileSecrets = ../profiles/${profile}/secrets.yaml;
in
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  # An age identity owned by the host itself, generated on first activation.
  # Preferred over deriving one from the SSH host key because wsl and orbstack
  # don't run openssh and so have no host keys to derive from.
  sops.age = {
    keyFile = "/var/lib/sops-nix/key.txt";
    generateKey = true;
  };

  # Only point at the profile's secrets file once it actually exists —
  # otherwise a profile that has no secrets yet fails to evaluate.
  sops.defaultSopsFile = lib.mkIf (builtins.pathExists profileSecrets) profileSecrets;

  environment.systemPackages = with pkgs; [
    sops
    age
    ssh-to-age
  ];
}
