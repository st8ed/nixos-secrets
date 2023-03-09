{ config, lib, ... }:

with lib;

{
  secrets.generators = {
    mkHostKey.private = path: secret: "get_hostkey '' ${escapeShellArg path}";
    mkHostKey.public = path: secret: "get_hostkey '.pub' ${escapeShellArg path}";
  };

  secrets.generatorScripts = [
    (pkgs: ''
      export PATH="${makeBinPath (with pkgs; [
        openssh
      ])}:$PATH"

      function get_hostkey() {
        local suffix="$1"
        local base_path="$2"
        local path="$base_path$suffix"

        if ! secret_read "$path"; then
          log GEN "generating $base_path using ssh-keygen"

          (
            tmpdir="$(mktemp -d)"
            trap 'rm -rf -- "$tmpdir"' EXIT
            cd "$tmpdir"

            ssh-keygen \
                -q -N "" -C "" \
                -f id \
                -t ed25519

            secret_write "$base_path" "$(cat ./id)"
            secret_write "$base_path.pub" "$(cat ./id.pub)"

            rm -rf -- "$tmpdir"
          )

          secret_read "$path"
        fi
      }
    '')
  ];
}
