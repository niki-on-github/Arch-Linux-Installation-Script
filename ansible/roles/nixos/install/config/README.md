# NixOS

This setup create the folder `/etc/nixos/config` with an minimal config. The idea is to use gitops pattern for this directory and track all the files in a git repository. I explicit exclude the `hardware-config` from this folder to allow an machine independent setup.
