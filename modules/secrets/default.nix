{ pkgs, config, lib, ... }:

with lib;

let
  cfg = config.secrets;

  enumerate = list: (zipListsWith
    (a: b: a // { index = b; })
    list
    (range 1 ((builtins.length list) + 1))
  );

  files = enumerate (
    toposort
      (a: b: builtins.elem a.name b.value.needs)
      (mapAttrsToList nameValuePair cfg.files)
  ).result;
in
{
  imports = [
    ./pki.nix

    ./generators/random.nix
    ./generators/hostkey-openssh.nix
    ./generators/cfssl.nix
    ./generators/kubeconfig.nix
  ];

  options = with types; {
    secrets.sopsFile = mkOption {
      type = path;
    };

    secrets.sopsFileLocal = mkOption {
      type = str;
    };

    secrets.hostKeyName = mkOption {
      type = str;
      default = "hostkey-${config.networking.hostName}";
    };

    secrets.files = mkOption {
      type = attrsOf (submodule ({ name, config, ... }: {
        options = {
          name = mkOption {
            type = str;
            readOnly = true;
            default = name;
          };

          needs = mkOption {
            type = listOf str;
            default = [ ];
          };

          generator = mkOption {
            type = anything;
          };

          command = mkOption {
            type = str;
            readOnly = true;
            internal = true;
            default = config.generator config;
          };

          mount = {
            enable = mkOption {
              type = bool;
              default = true;
            };

            path = mkOption {
              type = nullOr str;
              default = null;
            };

            user = mkOption {
              type = str;
              default = "root";
            };

            group = mkOption {
              type = str;
              default = "root";
            };

            mode = mkOption {
              type = str;
              default = "0400";
            };

            restartUnits = mkOption {
              type = listOf str;
              default = [ ];
            };

            reloadUnits = mkOption {
              type = listOf str;
              default = [ ];
            };
          };
        };
      }));
      default = { };
    };

    secrets.generators = mkOption {
      type = attrsOf anything;
    };

    secrets.generatorScripts = mkOption {
      type = listOf anything;
    };

    secrets.build.builder = mkOption {
      type = anything;
      readOnly = true;
    };

    secrets.build.toplevel = mkOption {
      type = package;
      readOnly = true;
      default = cfg.build.builder pkgs;
    };
  };

  config = {
    secrets.build.builder = pkgs: pkgs.writeShellApplication {
      name = "build-secrets-${config.system.name}-${config.system.nixos.label}";
      text = ''
        ${(concatStringsSep "\n" (
          map (g: g pkgs) cfg.generatorScripts
        ))}

        function generate() {
          # Note: we use sequential exports instead of --rawfile
          # with bash process substitution capture in order
          # to avoid parallel execution

          ${concatStringsSep "\n" (map (v:
          ''secret_${builtins.toString v.index}="$(get_secret ${escapeShellArgs [
              v.name v.value.command
          ]})"; export secret_${builtins.toString v.index}''
          ) files)}

          jq --null-input --compact-output \
            '{
            ${concatStringsSep ", " (map (v:
              ''"${v.name}": env.secret_${builtins.toString v.index}''
            ) (builtins.filter (v: v.value.mount.enable) files))}
            }'
        }

        function assemble() {
          local out="$1"
          local secrets="$2"

          local host_keys=""

          ${optionalString (config ? networking.hostName) ''
          host_keys="$(get_hostkey '.pub' ${escapeShellArg (
            cfg.hostKeyName
          )})"
          ''}

          local ret=0

          SOPS_PGP_FP="$(tr "\n" ',' <"$PASSWORD_STORE_DIR/.gpg-id" | head -c -1)" \
          SOPS_AGE_RECIPIENTS="$(ssh-to-age <<<"$host_keys")" \
            sops-update "$out" <<<"$secrets" || ret=$?

          if [ $ret -eq 0 ]; then
            echo "Updated $out"
          else
            echo "Could not update $out" >&2
            exit 1
          fi
        }

        assemble \
          "${cfg.sopsFileLocal}" \
          "$(generate)"

        log_end
      '';
    };

    secrets.generators = {
      static = text: secret: "echo -n ${escapeShellArg text}";
      external = path: secret: "secret_read ${escapeShellArg path}";
    };

    secrets.generatorScripts = [
      (pkgs: ''
        export PATH="${makeBinPath (with pkgs; [
          ncurses
        ])}:$PATH"

        GREEN="$(tput setaf 2)"
        EL0="$(tput el)"
        RESET="$(tput sgr0)"

        current_secret=""
        function log() {
          local line="$2"

          if [ -n "$current_secret" ]; then
            line="$current_secret: $line"
          fi

          echo -ne "[ $GREEN$1$RESET ] $line$EL0\n" >&2
        }

        function log_end() {
          echo -ne "$EL0" >&2
        }

        function get_secret() {
          local name="$1"
          local command="$2"

          current_secret="$name"
          echo -ne "[          ] $name$EL0\r" >&2

          # TODO: Add check for errors during generation
          # and if output is empty
          eval "$command"
        }
      '')
      (pkgs: ''
        export PATH="${makeBinPath (with pkgs; [
          pass # gnupg
          jq ssh-to-age
          (writeShellApplication {
            name = "sops-update";
            runtimeInputs = [ sops diffutils jq ];
            text = ''
            if [ -z "''${_IN_EDITOR-}" ]; then
                ret=0

                _IN_EDITOR=1 _EDITOR_DATA=<(cat /dev/stdin) EDITOR="$0" \
                  sops --in-place "''$@" \
                  >/dev/null 2>/dev/null \
                  \
                  || ret=$?

                # Return code: FileHasNotBeenModified = 200
                if [ $ret -ne 0 ] && [ $ret -ne 200 ]; then
                  exit $ret
                fi
            else
              _EDITOR_DATA="$(cat "$_EDITOR_DATA")"

              # Avoid file updates if there are no differences
              # Note: this does not sort nested array values!
              if ! diff \
                <(jq --sort-keys . <(echo -n "$_EDITOR_DATA")) \
                <(jq --sort-keys . "$1") \
                >/dev/null 2>/dev/null
              then
                echo -n "$_EDITOR_DATA" >"$1"
              fi
            fi
          ''; })
        ])}:$PATH"

        function secret_read() {
          pass show "$1" 2>/dev/null
        }

        function secret_write() {
          echo -n "$2" | pass insert -m "$1" >/dev/null
          # log "WRI" "$1"
        }
      '')
    ];

    # TODO: Currently only ed25519 host keys are allowed
    # because sops and ssh-to-pgp utility require
    # managing GPG keystore in home directory,
    # and it is an unnecessary burden
    services.openssh.hostKeys = mkForce [{
      path = "/etc/ssh/ssh_host_ed25519_key";
      rounds = 100;
      type = "ed25519";
    }];
  };
}
