# macOS laptop. Nix itself is installed and managed by Determinate Nix
# (https://determinate.systems) — there is no NixOS or nix-darwin layer here,
# so this profile is a standalone Home Manager configuration:
#
#   home-manager switch --flake .#macos
#
# `username` overrides the flake's default ("qt1"); `homeDirectory` is derived
# from the darwin `system` by flake.nix (/Users/... instead of /home/...).
{
  system = "aarch64-darwin";
  kind = "home";
  username = "quentin";
}
