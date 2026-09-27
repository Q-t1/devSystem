{ ... }:

{
  # The `coding` IDE's clipboard (config/common/home.nix imports the IDE). This
  # host is headless and only ever reached over SSH, so the clipboard goes
  # through OSC 52 terminal escapes — the copy lands in the clipboard of
  # whatever terminal is driving the session, not on the server.
  programs.codingIde.clipboardProvider = "osc52";
}
