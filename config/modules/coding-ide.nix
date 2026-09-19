# The `coding` IDE — yazi + zellij + nixvim — lives in its own flake now
# (`codide`, github:Q-t1/CodIDE, a sibling checkout at ../CodIDE). That flake
# owns the module; this file is the devSystem-specific glue every profile
# imports instead of the raw home module:
#
#   * `claude` comes from our own claude-code input, via the overlay that
#     config/modules/claude-code.nix / mkHome apply, so the whole repo ships
#     one `claude` build (and the cachix substituter that goes with it) rather
#     than pulling a second one through CodIDE.
#   * nixd is pointed at *this* flake's outputs, so option completion in a
#     home.nix / configuration.nix here is the real thing.
#
# A profile still only sets `programs.codingIde.clipboardProvider`.
{
  inputs,
  pkgs,
  profile,
  kind,
  ...
}:

{
  imports = [ inputs.codide.homeModules.default ];

  programs.codingIde = {
    claudeCode.package = pkgs.claude-code;

    # Scoped to *this* profile's own config since the module is shared across
    # hosts, and which output holds it depends on the profile's kind: NixOS
    # hosts embed Home Manager under `nixosConfigurations.<profile>`, while a
    # standalone host (macos) is a bare `homeConfigurations.<profile>` with no
    # NixOS options at all. `${inputs.self}` is the flake's store path — option
    # *names* come from the modules, not your values, so a pinned snapshot is
    # fine; nixpkgsExpr uses the flake's pinned nixpkgs.
    nixd = {
      nixpkgsExpr = ''import (builtins.getFlake "${inputs.self}").inputs.nixpkgs { }'';
      options =
        if kind == "nixos" then
          {
            nixos = ''(builtins.getFlake "${inputs.self}").nixosConfigurations.${profile}.options'';
            home-manager = ''(builtins.getFlake "${inputs.self}").nixosConfigurations.${profile}.options.home-manager.users.type.getSubOptions [ ]'';
          }
        else
          {
            home-manager = ''(builtins.getFlake "${inputs.self}").homeConfigurations.${profile}.options'';
          };
    };
  };
}
