{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      ansible
      (python39.withPackages (p: with p; [
        cryptography
      ]))
    ];

}
