{ config, lib, ... }:

with lib;

let
  cfg = config.secrets;

  pkiModule = with types; { name, config, ... }: {
    options = {
      name = mkOption {
        type = str;
        readOnly = true;
        default = name;
      };

      secretPath = mkOption {
        type = str;
        default = name;
      };



      ca = mkOption {
        default = opts: mkFiles config "ca" opts;
      };

      client = mkOption {
        default = name: opts: mkFiles config name opts;
      };


      certFile = mkOption {
        default = name: "/run/secrets/${config.name}-${name}.pem";
        readOnly = true;
      };

      keyFile = mkOption {
        default = name: "/run/secrets/${config.name}-${name}-key.pem";
        readOnly = true;
      };


      cn = mkOption {
        type = nullOr str;
        default = name;
      };

      altNames = mkOption {
        type = listOf str;
        default = [ ];
      };

      organization = mkOption {
        type = nullOr str;
        default = null;
      };

    };
  };

  mkFiles = cfg: name: { profile ? "client", csr ? { }, mount ? { } } @ opts:
    let
      inherit (config.secrets) generators;
      isCA = name == "ca";

      generatorOpts = {
        path = cfg.secretPath + "/" + name; # TODO: Check for path collisions
        ca = if isCA then "" else cfg.secretPath + "/ca";
        inherit profile;
        csr = {
          inherit (cfg) organization;
        } // (if isCA then {
          inherit (cfg) cn altNames;
        } else { }) // csr;
      };
    in
    assert true; {
      "${cfg.name}-${name}-key.pem" = {
        needs = mkIf (isCA != true) [ "${cfg.name}-ca-key.pem" ];

        generator = generators.mkCert.private generatorOpts;

        mount.enable = if (mount ? private) then mount.private else !isCA;
        mount.user = mkIf (mount ? user) mount.user;
        mount.mode = "0400";
      };

      "${cfg.name}-${name}.pem" = {
        needs = [ "${cfg.name}-${name}-key.pem" ];

        generator = generators.mkCert.public generatorOpts;

        mount.enable = if (mount ? public) then mount.public else true;
        mount.user = "root";
        mount.mode = "0444";
      };
    };

in
{
  options = with types; {
    secrets.pki = mkOption {
      type = attrsOf (submodule pkiModule);
      default = { };
    };
  };
}
