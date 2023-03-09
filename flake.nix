{
  inputs = {
    sops-nix.url = "github:Mic92/sops-nix";

    # Note:
    # nixpkgs and nixpkgs-stable inputs of sops-nix are not used
  };

  outputs = { self, sops-nix }: {
    nixosModule.imports = [
      sops-nix.nixosModules.sops
      ./modules/secrets
      ./modules/secrets/sops.nix
    ];
  };
}
