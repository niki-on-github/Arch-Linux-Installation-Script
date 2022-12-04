{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    nativeBuildInputs = with pkgs; [
      ansible
      (python3.withPackages (p: with p; [
        cryptography
      ]))
    ];

}
