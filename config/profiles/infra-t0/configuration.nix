{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ../../modules/boot-efi.nix
    ../../modules/locale-fr.nix
    ../../modules/openssh.nix
    ../../modules/user-qt1-server.nix
  ];

  nix.package = pkgs.nix;

  # coding-ide (imported by home.nix) pulls the unfree claude-code, same as
  # the wsl/orbstack profiles.
  nixpkgs.config.allowUnfree = true;

  swapDevices = [
    {
      device = "/swapfile";
      size = 8192;
    }
  ];

  networking = {
    hostName = "infra-t0";
    useDHCP = false;
    dhcpcd.enable = false;
    interfaces.br-lan = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.230";
          prefixLength = 24;
        }
      ];
    };
    bridges.br-lan = {
      interfaces = [ "enp2s0" ];
    };
    wireless.enable = false;
    defaultGateway = "192.168.1.254";
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  system.stateVersion = "26.05";
}
