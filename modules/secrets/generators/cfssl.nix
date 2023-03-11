{ config, lib, ... }:

with lib;

let
  # FIXME: Configurable defaults for certs
  defaults = {
    csr.key.algo = "rsa";
    csr.key.size = 3072;
    expiry = "2190h";
  };

  mkCsr = { cn, altNames ? [ ], organization ? null }: (builtins.toJSON (lib.attrsets.recursiveUpdate defaults.csr {
    CN = cn;
    hosts = [ cn ] ++ altNames;
    names = if organization == null then null else [
      { "O" = organization; }
    ];
  }));

  caConfig = builtins.toFile "ca-config.json" (builtins.toJSON {
    signing.profiles = {
      server = { inherit (defaults) expiry; usages = [ "signing" "key encipherment" "client auth" "server auth" ]; };
      client = { inherit (defaults) expiry; usages = [ "signing" "key encipherment" "client auth" ]; };
      peer = { inherit (defaults) expiry; usages = [ "signing" "key encipherment" "client auth" ]; };
    };
  });

in
{
  config = {
    secrets.generatorScripts = [
      (pkgs: ''
        export PATH="${makeBinPath (with pkgs; [
          cfssl
        ])}:$PATH"

        function get_cfssl_cert() {
          local suffix="$1"
          local base_path="$2"
          local ca="$3"
          local profile="$4"
          local csr="$5"

          local path="$base_path$suffix"

          if ! secret_read "$path"; then
            log GEN "using cfssl, base path: $base_path"

            (
              tmpdir="$(mktemp -d)"
              trap 'rm -rf -- "$tmpdir"' EXIT
              cd "$tmpdir"

              if [ -z "$ca" ]; then
                cfssl gencert -loglevel 2 -initca <(echo -n "$csr") \
                  | cfssljson -bare ./cert
              else
                cfssl gencert \
                    -loglevel 2 \
                    -ca <(secret_read "$ca") \
                    -ca-key <(secret_read "$ca-key") \
                    -config "${caConfig}" \
                    -profile "$profile" \
                    <(echo -n "$csr") \
                    | cfssljson -bare ./cert
              fi

              secret_write "$base_path" "$(cat ./cert.pem)"
              secret_write "$base_path-key" "$(cat ./cert-key.pem)"

              rm -rf -- "$tmpdir"
            )

            secret_read "$path"
          fi
        }
      '')
    ];

    secrets.generators = {
      mkCert.private = { path, ca, profile, csr }: secret: "get_cfssl_cert '-key' ${escapeShellArgs [ path ca profile (mkCsr csr) ]}";
      mkCert.public = { path, ca, profile, csr }: secret: "get_cfssl_cert '' ${escapeShellArgs [ path ca profile (mkCsr csr) ]}";
    };
  };
}
