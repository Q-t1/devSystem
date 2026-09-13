# MicroVM host side: the microvm.nix host module, the NAT'd bridge the guests
# sit on, and the declarative guests themselves (one file each under
# ./microvms/). Guests are rebuilt and restarted by `nixos-rebuild switch`.
{ inputs, ... }:

let
  # Dashboard-managed tunnel token, provisioned by hand (see README). Read by
  # qemu, which runs as the `microvm` user, and passed into the guest as a
  # systemd credential so it never lands in the Nix store.
  cloudflaredTokenFile = "/var/lib/microvms/cloudflared/tunnel-token";
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  microvm.vms.cloudflared.config = {
    imports = [ ./microvms/cloudflared.nix ];
    microvm.credentialFiles.tunnel-token = cloudflaredTokenFile;
  };

  # Keep the VM stopped (skipped, not failed) until the token exists; start it
  # with `systemctl start microvm@cloudflared` once provisioned.
  systemd.services."microvm@cloudflared".unitConfig.ConditionPathExists = cloudflaredTokenFile;

  # Guest network 10.100.0.0/24, host at .1. Only this bridge and the guests'
  # tap devices are handed to networkd; enp2s0 stays on the scripted
  # networking in configuration.nix.
  systemd.network = {
    enable = true;
    # networkd manages no uplink here, so waiting on it would only stall boot.
    wait-online.enable = false;

    netdevs."10-microvm".netdevConfig = {
      Kind = "bridge";
      Name = "microvm";
    };
    networks."10-microvm" = {
      matchConfig.Name = "microvm";
      address = [ "10.100.0.1/24" ];
      # Keep the address while no guest is attached.
      networkConfig.ConfigureWithoutCarrier = true;
    };
    # Tap devices are created by microvm-tap-interfaces@<vm> as `vm-*`.
    networks."11-microvm-taps" = {
      matchConfig.Name = "vm-*";
      networkConfig.Bridge = "microvm";
    };
  };

  # Guests reach the internet and the LAN masqueraded behind 192.168.1.230.
  networking.nat = {
    enable = true;
    internalInterfaces = [ "microvm" ];
    externalInterface = "enp2s0";
  };
}
