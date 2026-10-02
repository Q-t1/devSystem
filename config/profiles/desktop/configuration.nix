{ inputs, ... }:

{
  imports = [
    # The whole host layer — hardware, disko layout, lanzaboote/TPM2, graphics,
    # audio, gaming, fonts, locale, networking, the user accounts (including
    # cecile's Home Manager config) and niri/DMS at the system level. See
    # ../../../README.md and the configuration-manager repo.
    inputs.configuration-manager.nixosModules.default
  ];

  networking.hostName = "desktop-qt1";

  system.stateVersion = "26.05";
}
