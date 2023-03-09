{ config, lib, ... }:

with lib;

{
  secrets.generators = {
    kubeconfig = { path, server, caPath, certPath }: secret: "get_kubeconfig ${escapeShellArgs [
      path server caPath certPath
    ]}";
  };

  secrets.generatorScripts = [
    (pkgs: ''
      export PATH="${makeBinPath (with pkgs; [
        kubectl
      ])}:$PATH"

      function get_kubeconfig() {
        local path="$1"
        local server="$2"
        local ca_cert="$3.pem"
        local client_cert="$4.pem"
        local client_key="$4-key.pem"

        if ! secret_read "$path"; then
          log GEN "using kubectl config"

          (
            tmpdir="$(mktemp -d)"
            trap 'rm -rf -- "$tmpdir"' EXIT
            cd "$tmpdir"

            export KUBECONFIG="$tmpdir/kubeconfig"
            touch "$KUBECONFIG"

            kubectl config set-cluster default \
                --embed-certs=true \
                --certificate-authority=<(secret_read "$ca_cert") \
                --server="$server"

            kubectl config set-credentials default \
                --embed-certs=true \
                --client-certificate=<(secret_read "$client_cert") \
                --client-key=<(secret_read "$client_key")


            kubectl config set-context default \
                --user default \
                --cluster default

            kubectl config use-context default

            secret_write "$path" "$(cat ./kubeconfig)"

            rm -rf -- "$tmpdir"
          )

          secret_read "$path"
        fi
      }
    '')
  ];
}
