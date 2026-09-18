{ ... }:

{
  # The `coding` IDE (yazi + zellij + nixvim), same as wsl/macos. This host is
  # headless and only ever reached over SSH, so the clipboard goes through OSC
  # 52 terminal escapes — the copy lands in the clipboard of whatever terminal
  # is driving the session, not on the server.
  imports = [ ../../modules/coding-ide ];

  programs.codingIde.clipboardProvider = "osc52";
}
