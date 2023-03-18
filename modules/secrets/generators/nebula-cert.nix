{ config, lib, ... }:

with lib;

let
  # FIXME: Configurable defaults for certs
  defaults = {
    duration = "8760h"; # 1 year
    subnets = null; # for instance "10.0.0.0/16"
    groups = null;
  };

in
{
  config = {
    secrets.generatorScripts = [
      (pkgs: ''
        export PATH="${makeBinPath (with pkgs; [
          nebula
        ])}:$PATH"

        function get_nebula_cert() {
          local suffix="$1"
          local base_path="$2"
          local ca="$3"
          local name="$4"
          local ip="$5"
          local subnets="$6"
          local groups="$7"

          local path="$base_path$suffix"

          if ! secret_read "$path"; then
            log GEN "using nebula-cert, base_path: $base_path"

            (
              tmpdir="$(mktemp -d)"
              trap 'rm -rf -- "$tmpdir"' EXIT
              cd "$tmpdir"

              if [ -z "$ca" ]; then
                nebula-cert ca \
                    -name "$name" \
                    ${lib.optionalString (defaults.subnets != null) ''-subnets ${lib.escapeShellArg defaults.subnets}''} \
                    ${lib.optionalString (defaults.groups != null) ''-subnets ${lib.escapeShellArg defaults.groups}''} \
                    -duration ${lib.escapeShellArg defaults.duration} \
                    -out-crt cert.crt \
                    -out-key cert.key
              else
                nebula-cert sign \
                      -ca-crt <(secret_read "$ca") \
                      -ca-key <(secret_read "$ca-key") \
                      -name "$name" \
                      -ip "$ip" \
                      -subnets "$subnets" \
                      -groups "$groups" \
                      -out-crt cert.crt \
                      -out-key cert.key
              fi

              secret_write "$base_path" "$(cat ./cert.crt)"
              secret_write "$base_path-key" "$(cat ./cert.key)"

              rm -rf -- "$tmpdir"
            )

            secret_read "$path"
          fi
        }
      '')
    ];

    secrets.generators = {
      mkNebulaCert.private = { path, ca, name, ip, subnets, groups }: secret: "get_nebula_cert '-key' ${escapeShellArgs [ path ca name ip subnets groups ]}";
      mkNebulaCert.public = { path, ca, name, ip, subnets, groups }: secret: "get_nebula_cert '' ${escapeShellArgs [ path ca name ip subnets groups ]}";
    };
  };
}
