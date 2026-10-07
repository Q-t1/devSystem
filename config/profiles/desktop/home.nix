{ inputs, ... }:

{
  imports = [
    # qt1's desktop session: niri settings and keybinds, DankMaterialShell,
    # Firefox, the polkit agent and hypridle, GTK theme and cursor.
    inputs.configuration-manager.homeModules.default
  ];

  # The `coding` IDE's clipboard (config/common/home.nix imports the IDE). This
  # is the wl-clipboard-backed provider — the same one WSLg needs, hence the
  # name — which is what a native Wayland session (niri) wants too.
  programs.codingIde.clipboardProvider = "wsl";
}
