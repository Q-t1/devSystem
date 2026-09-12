{ ... }:

{
  # The `coding` IDE (yazi + zellij + nixvim). infra-t0 is a headless
  # bare-metal server reached over SSH, so the clipboard rides OSC 52 escapes
  # (same as orbstack) rather than the WSL/Windows bridge.
  imports = [ ../../modules/coding-ide ];
}
