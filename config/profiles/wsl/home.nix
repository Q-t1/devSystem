{
  pkgs,
  lib,
  config,
  ...
}:

{
  imports = [ ../../modules/coding-ide.nix ];

  # WSL reaches the Windows clipboard directly (WSLg Wayland with a clip.exe /
  # PowerShell fallback) rather than OSC 52.
  programs.codingIde.clipboardProvider = "wsl";

  home.packages = with pkgs; [
    skopeo
    jq
    yq
    kubectl
    kubernetes-helm
    kustomize
    kubeconform
    openssl
    fluxcd
  ];

  programs.git.settings.user.email = lib.mkForce "quentin.roccia@bleucloud.fr";

  programs.firefox = {
    enable = true;
    policies.Certificates.Install = [ "${./certs/bleu-rootca.pem}" ];
    profiles.default = {
      search = {
        default = "google";
        force = true;
      };
      settings = {
        "layers.acceleration.disabled" = true;
        "gfx.webrender.compositor" = false;
      };
    };
  };

  # Certificates.Install policy doesn't persist to the NSS db on Linux;
  # import directly via certutil on every home-manager activation instead.
  home.activation.firefoxTrustBleuCA = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ffProfile="${config.home.homeDirectory}/${config.programs.firefox.profilesPath}/default"
    certFile="${./certs/bleu-rootca.pem}"
    if [[ -d "$ffProfile" ]] && [[ -f "$ffProfile/cert9.db" ]]; then
      if ! ${pkgs.nss.tools}/bin/certutil -L -d "$ffProfile" 2>/dev/null | grep -q "bleu.local"; then
        run ${pkgs.nss.tools}/bin/certutil -A \
          -n "bleu.local-SUBCA1-Issuing-CA" \
          -t "CT,C,C" \
          -i "$certFile" \
          -d "$ffProfile"
      fi
    fi
  '';

  programs.zsh.shellAliases.ff = "MOZ_ENABLE_WAYLAND=1 firefox &>/dev/null & disown";
}
