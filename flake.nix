{
  description = "Environment to package a tauri app";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-20.09";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  #inputs.naersk.url = "github:nmattia/naersk";
  inputs.melwalletd-flake.url = "github:themeliolabs/melwalletd";
  inputs.mozilla = { url = "github:mozilla/nixpkgs-mozilla"; flake = false; };
  inputs.tauriSrc = { url = "github:tauri-apps/tauri/cli.js-v1.0.0-beta.2"; flake = false; };

  outputs =
    { self
    , nixpkgs
    , mozilla
    , flake-utils
    , tauriSrc
    , melwalletd-flake
    , ...
    } @inputs:
    let rustOverlay = final: prev:
      let rustChannel = prev.rustChannelOf {
        channel = "1.52.0";
        sha256 = "sha256-fcaq7+4shIvAy0qMuC3nnYGd0ZikkR5ln/rAruHA6mM=";
      };
      in
      { inherit rustChannel;
        rustc = rustChannel.rust;
        cargo = rustChannel.rust;
      };

    in flake-utils.lib.eachSystem
      ["x86_64-linux"]
      (system: let

        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (import "${mozilla}/rust-overlay.nix")
            rustOverlay
          ];
        };

        rustPlatform = let rustChannel = pkgs.rustChannelOf {
            channel = "1.52.0";
            sha256 = "sha256-fcaq7+4shIvAy0qMuC3nnYGd0ZikkR5ln/rAruHA6mM=";
          }; in
            pkgs.makeRustPlatform {
              cargo = rustChannel.rust;
              rustc = rustChannel.rust;
            };

        #naersk-lib = naersk.lib."${system}";
        tauri = rustPlatform.buildRustPackage rec {
          pname = "tauri-v${version}";
          version = "1.0.0-beta.2";
          src = "${tauriSrc}";
          sourceRoot = "source/tooling/cli.rs";
          cargoSha256 = "sha256-v1dFLI8J3Ksg+lkw9fAwTYytXkj3ZLlB6086LPy9ZxY=";
        };

        melwalletd = melwalletd-flake.packages."${system}".melwalletd;

        bundleDrv = pkgs.callPackage ./bundle.nix {};

        tauri-deps = with pkgs; [
              binutils
              zlib
              wget
              curl
              openssl
              squashfsTools
              pkg-config
              libsoup

              webkit
              gtk3-x11
              gtksourceview
              libayatana-appindicator-gtk3
        ];

        in rec {
          /*
          packages.tauri = naersk-lib.buildPackage rec {
            name = "tauri-v${version}";
            version = "1.0.0-beta.2";

            src = "${tauriSrc}";
            root = "${tauriSrc}/tooling/cli.rs";

            buildInputs = with pkgs; [
              nodePackages.npm
            ] ++ tauri-deps;
          };
          */
          melwalletd = melwalletd-flake.packages."${system}".melwalletd;

          packages.tauri = tauri;

          # TODO this should not be
          defaultPackage = packages.tauri;

          devShell = pkgs.mkShell {
            buildInputs = with pkgs; [
              #packages.tauri
              (rustChannel.rust.override { extensions = [ "rust-src" ]; })
            ] ++ tauri-deps;

            shellHook = ''
              export OPENSSL_DIR="${pkgs.openssl.dev}"
              export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib"

              # melwalletd
              export PATH=$PATH:${melwalletd}/bin
              # Place into project for bundling
              cp ${melwalletd}/bin/melwalletd ${self}/src-tauri/

              # Tauri cli
              export PATH=$PATH:${packages.tauri}/bin
              alias tauri='cargo-tauri'
            '';
          };
        });
}
