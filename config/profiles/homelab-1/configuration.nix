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
    firewall.allowedTCPPorts = [ 22 ];
  };

  # Infra layer, owned by the Qt1-Infrastructure flake. Only the uplink is an
  # OS fact this profile has to hand over.
  qt1.infra = {
    microvmHost = {
      enable = true;
      uplinkInterface = "enp2s0";
    };
    guests.cloudflared = {
      enable = true;
      # Reaches the same tailnet as the host itself, below.
      tailscale.enable = true;
    };
    guests.headscale = {
      enable = true;
      serverUrl = "https://headscale.qt1.fr";
      baseDomain = "tailnet.qt1.fr";
      headplaneUrl = "https://headplane.qt1.fr";
      # qt1's own key, so `ssh root@10.100.0.3` from this host works for
      # one-off `headscale` CLI commands.
      adminSshKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEZwHQueTTuhfMB98jXNBGC+z0GwEOv8+hGLaI5DSVj8IUxF9t7Bzcw3AK6yiRhbqz0PMrep1McwiKZ/z2KSbR8= qt1@nixos-foundation";
    };
    # This host is itself a tailnet member, not just the guests' coordinator.
    # loginServerUrl is headscale's bridge-local address, not the public
    # https://headscale.qt1.fr: Cloudflare Tunnel doesn't pass through the
    # Upgrade header Tailscale's registration protocol needs, but this host
    # can already reach the guest bridge directly, so there's no reason to
    # round-trip through the WAN anyway (see
    # qt1.infra.guests.headscale.serverUrl's description). authKeyFile is the
    # same auto-minted key the cloudflared guest uses above — nothing to
    # provision by hand.
    tailscaleClient = {
      enable = true;
      loginServerUrl = config.qt1.infra.guests.headscale.internalUrl;
      authKeyFile = config.qt1.infra.guests.headscale.tailscaleAuthKeyFile;
    };
  };

  # Not strictly required (tailscale-autoconnect retries on its own), but
  # avoids a spin of failed attempts while the key is still being minted.
  systemd.services.tailscale-autoconnect = {
    wants = [ "headscale-mint-tailscale-authkey.service" ];
    after = [ "headscale-mint-tailscale-authkey.service" ];
  };

  system.stateVersion = "26.05";
}
