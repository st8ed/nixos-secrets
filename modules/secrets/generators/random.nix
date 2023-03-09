{ config, lib, ... }:

with lib;

{
  secrets.generators = {
    random = path: method: length: secret: "get_random ${escapeShellArgs [ path method length ]}";
  };
  secrets.generatorScripts = [
    (pkgs: ''
      export PATH="${makeBinPath (with pkgs; [
        coreutils
      ])}:$PATH"

      function get_random() {
        local path="$1"
        local method="$2"
        local length="$3"

        if ! secret_read "$path"; then
          log GEN "using random/$method"

          local secret
          secret="$(eval "random_$method $length")"

          secret_write "$path" "$secret"
          echo -n "$secret"
        fi
      }

      function random_hex() {
        LC_ALL=C tr -cd '0-9a-f' </dev/urandom | head -c"$1"
      }

      function random_alphanum() {
        LC_ALL=C tr -cd '[:alnum:]' </dev/urandom | head -c"$1"
      }
    '')
  ];
}
