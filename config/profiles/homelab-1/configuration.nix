{
  inputs,
  pkgs,
  config,
  ...
}:

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

  # coding-ide (see home.nix) pulls in the unfree `claude-code`.
  nixpkgs.config.allowUnfree = true;

  # Ghostty's terminfo entry, system-wide. config/common/home.nix already puts
  # it in qt1's Home Manager profile, but that is only reachable through the
  # TERMINFO_DIRS that hm-session-vars exports — root (`sudo -i`, the physical
  # console) never sources it. Here it lands in
  # /run/current-system/sw/share/terminfo, which ncurses searches by default,
  # so `TERM=xterm-ghostty` resolves for every user on this SSH target.
  environment.systemPackages = [ pkgs.ghostty.terminfo ];

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
    firewall.allowedTCPPorts = [
      22
      80
      443
    ];
  };

  # Infra layer, owned by the Qt1-Infrastructure flake. Only the uplink is an
  # OS fact this profile has to hand over.
  qt1.infra = {
    microvmHost = {
      enable = true;
      uplinkInterface = "enp2s0";
    };
    guests.headscale = {
      enable = true;
      serverUrl = "https://access.qt1.fr";
      # Must differ from serverUrl's domain (see the option doc); ts.qt1.fr
      # is otherwise unused.
      baseDomain = "ts.qt1.fr";
      letsEncryptEmail = "quentin.roccia@gmail.com";
      # Same key user-qt1-server.nix already authorizes for qt1 on this
      # host, reused here for root on the headscale guest.
      adminSshKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDtASdfLMatnUWsdJIjIvIXqXrnmABAznN/6mji1/rzRLqrusduqahyi4htTRvOuue3vrhUqeywiRTNTpzthfhVqeF5WehE1wAPkbgGwAvxC8ltqLPza6KkfZF0WXdXj/MsKJDTJUwui+acbyJocuMz0teJOhURoaEetXzr+ffj6P9Txz7uX6KN8D2DYGi9WvG8QPdlF/89f5vtCx4GFrKkdSET+yNC3PEcf+X8wDoL+ztuvcTGLb4rC42NzLJ82VCAYZ6KS085s8GD+lcgU/jxpRUeCVoY7Ciym/VKs2oxVsyM45fP+d33BJmqV+WGgVLHz0T4y05HOS6CBLObbXZYLfDg7jNl/MVxVktNRfvPLr23z8IvUL1DR8lHIqc6jesFMe8W5PuaoxwzQIhRl8ywGT/rVq1btMiS41mqo/86pZAFtehTt04A3GbMVGB7NNO3tmaVbUlr/aSFdB/hLr0pU3uuZQsHCipZ/3+IGs7erU1r2VVNhnxd/JcDJEVstd8= quentin@MacBook-Air-de-Quentin.local";
    };
    # Join the host itself to its own tailnet, so it's reachable over
    # Tailscale (e.g. for SSH) the same way any other tailnet member is.
    # See Qt1-Infrastructure's README, "Joining the tailnet".
    tailscaleClient = {
      enable = true;
      loginServerUrl = config.qt1.infra.guests.headscale.serverUrl;
      authKeyFile = config.qt1.infra.guests.headscale.tailscaleAuthKeyFile;
    };
  };

  # Bridge-local shortcut for the tailscaleClient join above: resolves
  # serverUrl's hostname straight to the headscale guest's bridge address
  # instead of out through the WAN and back in via the router's port
  # forward (NAT hairpinning, which not every router supports reliably).
  networking.hosts.${config.qt1.infra.guests.headscale.address} = [
    config.qt1.infra.guests.headscale.tlsHostname
  ];

  system.stateVersion = "26.05";
}
