{ inputs, ... }:

{
  imports = [
    ./hardware.nix
    # microVM host layer and guests; see ../../../README.md and the
    # Qt1-Infrastructure repo.
    inputs.qt1-infrastructure.nixosModules.default
    ../../modules/boot-efi.nix
    ../../modules/locale-fr.nix
    ../../modules/openssh.nix
    ../../modules/user-qt1-server.nix
  ];

  networking = {
    hostName = "homelab-1";
    useDHCP = false;
    dhcpcd.enable = false;
    interfaces.enp2s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.230";
          prefixLength = 24;
        }
      ];
    };
    wireless.enable = false;
    defaultGateway = "192.168.1.254";
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
    firewall.allowedTCPPorts = [ 22 ];
  };

  # Infra layer, owned by the Qt1-Infrastructure flake. Only the uplink is an
  # OS fact this profile has to hand over.
  qt1.infra = {
    microvmHost = {
      enable = true;
      uplinkInterface = "enp2s0";
    };
    guests.cloudflared.enable = true;
  };

  system.stateVersion = "26.05";
}
