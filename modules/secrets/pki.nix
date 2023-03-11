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

      format = mkOption {
        type = enum [ "x509" "nebula" ];
        default = "x509";
      };


      ca = mkOption {
        default = opts: mkFiles config "ca" opts;
      };

      client = mkOption {
        default = name: opts: mkFiles config name opts;
      };


      certFile = mkOption {
        default = name: "/run/secrets/${config.name}-${name}";
        readOnly = true;
      };

      keyFile = mkOption {
        default = name: "/run/secrets/${config.name}-${name}-key";
        readOnly = true;
      };


      cn = mkOption {
        type = nullOr str;
        default = name;
      };

      organization = mkOption {
        type = nullOr str;
        default = null;
      };
    };
  };

  mkFiles = cfg: name: { profile ? "client", csr ? { }, mount ? { } } @ opts:
    let
      isCA = name == "ca";

      generators = {
        inherit (if cfg.format == "x509" then
          config.secrets.generators.mkCert
        else if cfg.format == "nebula" then
          config.secrets.generators.mkNebulaCert
        else { }) private public;
      };

      generatorOpts = {
        # TODO: Check for path collisions there and in secret file names
        path = cfg.secretPath + "/" + name;
        ca = if isCA then "" else cfg.secretPath + "/ca";
      }

      // (lib.optionalAttrs (cfg.format == "x509") {
        inherit profile;
        csr = {
          inherit (cfg) organization;
        } // (lib.optionalAttrs isCA {
          inherit (cfg) cn;
        }) // csr;
      })

      // (lib.optionalAttrs (cfg.format == "nebula" && isCA) {
        name = cfg.cn;
        ip = "";
        groups = "";
      })
      // (lib.optionalAttrs (cfg.format == "nebula" && !isCA) {
        name = csr.cn;
        ip = assert (builtins.length csr.altNames == 1); builtins.head csr.altNames;
        groups = if csr ? organization then csr.organization else "";
      });

    in
    assert true; {
      "${cfg.name}-${name}-key" = {
        needs = mkIf (isCA != true) [ "${cfg.name}-ca-key" ];

        generator = generators.private generatorOpts;

        mount.enable = if (mount ? private) then mount.private else !isCA;
        mount.user = mkIf (mount ? user) mount.user;
        mount.mode = "0400";
      };

      "${cfg.name}-${name}" = {
        needs = [ "${cfg.name}-${name}-key" ];

        generator = generators.public generatorOpts;

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
