{
  pkgs,
  lib,
  config,
  ...
}:

{
  # The `coding` IDE's clipboard (config/common/home.nix imports the IDE):
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
    git-credential-manager
  ];

  programs.git.settings.user.email = lib.mkForce "quentin.roccia@bleucloud.fr";
  programs.git.settings.credential = {
    helper = "manager";
    azreposCredentialType = "oauth";
    # GCM on Linux needs an explicit store; keep credentials in memory.
    credentialStore = "cache";
    # Normally written by `git-credential-manager configure`; lets GCM read the
    # org name from the URL path.
    "https://dev.azure.com".useHttpPath = true;
    # GCM writes these to the global config at runtime, which home-manager makes
    # read-only, so pin them here. Bind the bleucloud org to this account (GCM
    # ignores the `bleucloud@` in clone URLs since it's just the org name), and
    # pre-seed its Entra tenant (from the org's `x-vss-resourcetenant` header).
    "azrepos:org/bleucloud" = {
      username = "quentin.roccia@bleucloud.fr";
      azureAuthority = "https://login.microsoftonline.com/1e28a902-ddbd-4e5d-afc8-4f273a735d06";
    };
  };

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
