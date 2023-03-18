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
        age busybox
      ])}:$PATH"

      function get_hostkey() {
        local suffix="$1"
        local base_path="$2"
        local path="$base_path$suffix"

        if ! secret_read "$path"; then
          log GEN "generating $base_path using age-keygen"

          (
            tmpdir="$(mktemp -d)"
            trap 'rm -rf -- "$tmpdir"' EXIT
            cd "$tmpdir"

            pubkey="$(age-keygen -o key.txt 2>&1 | cut -f3 -d' ')"

            secret_write "$base_path" "$(cat ./key.txt)"
            secret_write "$base_path.pub" "$pubkey"

            rm -rf -- "$tmpdir"
          )

          secret_read "$path"
        fi
      }
    '')
  ];
}
