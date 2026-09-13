# Cloudflare Tunnel entrypoint into the local infrastructure. The tunnel is
# dashboard-managed: public hostnames and private routes live in Cloudflare
# Zero Trust, so the VM only needs the tunnel token. That token comes from the
# host as the `tunnel-token` systemd credential (see ../microvms.nix).
#
# Stateless: the root filesystem is tmpfs and there is no SSH. The tunnel's
# logs are mirrored to the serial console, so they show up on the host with
# `journalctl -u microvm@cloudflared`.
{ pkgs, ... }:

let
  mac = "02:00:00:00:00:01";
in
{
  microvm = {
    # credentialFiles is only implemented by the qemu runner.
    hypervisor = "qemu";
    vcpu = 1;
    mem = 512;
    interfaces = [
      {
        type = "tap";
        id = "vm-cloudflared";
        inherit mac;
      }
    ];
  };

  # Credentials arrive over qemu's fw_cfg; its sysfs interface is a module, so
  # load it early enough for systemd to import them at boot.
  boot.initrd.kernelModules = [ "qemu_fw_cfg" ];

  networking = {
    useNetworkd = true;
    useDHCP = false;
    nameservers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };
  systemd.network.networks."10-uplink" = {
    matchConfig.MACAddress = mac;
    address = [ "10.100.0.2/24" ];
    gateway = [ "10.100.0.1" ];
  };

  # quic-go, which cloudflared uses to reach the edge, wants bigger UDP
  # buffers than the kernel default.
  boot.kernel.sysctl = {
    "net.core.rmem_max" = 7500000;
    "net.core.wmem_max" = 7500000;
  };

  environment.systemPackages = [ pkgs.cloudflared ];

  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %d/tunnel-token";
      ImportCredential = "tunnel-token";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = "5s";
      StandardOutput = "journal+console";
      StandardError = "journal+console";
    };
  };

  system.stateVersion = "26.05";
}
