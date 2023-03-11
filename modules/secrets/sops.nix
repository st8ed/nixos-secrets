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

      # TODO: Currently only ed25519 host keys are allowed
      # because sops and ssh-to-pgp utility require
      # managing GPG keystore in home directory,
      # and it is an unnecessary burden
      # services.openssh.hostKeys = mkForce [{
      #   path = "/etc/ssh/ssh_host_ed25519_key";
      #   rounds = 100;
      #   type = "ed25519";
      # }];
      gnupg.sshKeyPaths = [];
    };

  };
}
