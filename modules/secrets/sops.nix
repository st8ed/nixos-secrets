{ config, pkgs, lib, ... }:

with lib;

{
  config = {
    sops = {
      defaultSopsFile = config.secrets.sopsFile;

      secrets = mapAttrs
        (n: v: {
          path = mkIf (v.mount.path != null) v.mount.path;
          owner = v.mount.user;
          group = v.mount.group;
          mode = v.mount.mode;

          inherit (v.mount) restartUnits reloadUnits;
        })
        (filterAttrs
          (
            n: v: v.mount.enable
          )
          config.secrets.files);

      age.keyFile = "/var/lib/sops-nix/key.txt";

      # Delete defaults
      age.sshKeyPaths = [];
      gnupg.sshKeyPaths = [];
    };

  };
}
