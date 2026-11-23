{
  description = "Nearby Pharmacies iOS development tools";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      devShells.aarch64-darwin.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          betterleaks
          git
          jq
        ];
      };
    };
}
