{
  description = "Home Automation NixOS Configuration for sensors";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, ... }@inputs: {
    nixosConfigurations.sensors = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      specialArgs = { inherit inputs; };

      modules = [
        # Hardware configuration
        ./hardware-configuration.nix

        # Main configuration
        ./configuration.nix

        # Secrets management
        sops-nix.nixosModules.sops
      ];
    };
  };
}
