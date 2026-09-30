{ inputs, pkgs, ... }:

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

  # coding-ide (config/common/home.nix) pulls in the unfree `claude-code`.
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
      # homelab-1's own SSH host identity, trusted for root on every guest
      # that exposes SSH by default — lets the host itself (not just a
      # human's laptop) reach a guest as root, e.g. for troubleshooting from
      # a `qt1` shell on this box without copying a personal private key
      # onto the server.
      adminSshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOOU1fciGd3S4aJ7pnN10sMkKirklTuED/qhDbSmFdti root@nixos-foundation"
      ];
    };
    guests.headscale = {
      enable = true;
      serverUrl = "https://access.qt1.fr";
      # Must differ from serverUrl's domain (see the option doc); ts.qt1.fr
      # is otherwise unused.
      baseDomain = "ts.qt1.fr";
      # Combined with microvmHost.adminSshKeys above for root on this guest.
      adminSshKeys = [ ];
      # Headscale's web UI, tailnet-only behind caddyInternal, at
      # https://headplane.ts.qt1.fr/admin (headplane.url). See
      # Qt1-Infrastructure's README.
      headplane.enable = true;
    };
    # Fronts headscale with TLS; see Qt1-Infrastructure's README.
    guests.caddy = {
      enable = true;
      letsEncryptEmail = "quentin.roccia@gmail.com";
    };
    # Watches caddy's access log and bans offenders at the host firewall;
    # see Qt1-Infrastructure's README, "Protecting caddy".
    crowdsec.enable = true;
    # Tailnet-only reverse proxy for internal apps, each at its own
    # MagicDNS name (<label>.ts.qt1.fr); see Qt1-Infrastructure's README,
    # "caddy-internal guest".
    guests.caddyInternal.enable = true;
    # Loki+Prometheus+Grafana, behind caddyInternal: reachable only over the
    # tailnet, at http://grafana.ts.qt1.fr/ (grafanaUrl). See
    # Qt1-Infrastructure's README, "monitoring guest".
    guests.monitoring.enable = true;
    # Public status page, served by caddy at https://status.qt1.fr/ (needs
    # the DNS record, like access.qt1.fr). Checks headscale and every
    # caddyInternal app on its own; see Qt1-Infrastructure's README, "gatus
    # guest".
    guests.gatus = {
      enable = true;
      hostname = "status.qt1.fr";
    };
    # Join the host itself to its own tailnet, so it's reachable over
    # Tailscale (e.g. for SSH) the same way any other tailnet member is.
    # Login server, pre-auth key and the bridge shortcut to headscale all
    # default to the guests above; see Qt1-Infrastructure's README, "Joining
    # the tailnet".
    tailscaleClient.enable = true;
  };

  system.stateVersion = "26.05";
}
