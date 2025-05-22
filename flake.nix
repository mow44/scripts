{
  description = "A bunch of useful scripts";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # NOTE dirty hack to get interactive shell in writeShellApplication
        # Actually this is writeShellApplication implementation from
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/trivial-builders/default.nix
        # with selectable shell
        writeWithShellApplication =
          {
            name,
            shell ? "${pkgs.stdenv.shell}", # TODO make a pull request?
            text,
            runtimeInputs ? [ ],
            runtimeEnv ? null,
            meta ? { },
            passthru ? { },
            checkPhase ? null,
            excludeShellChecks ? [ ],
            extraShellCheckFlags ? [ ],
            bashOptions ? [
              "errexit"
              "nounset"
              "pipefail"
            ],
            derivationArgs ? { },
            inheritPath ? true,
          }:
          with pkgs;
          pkgs.writeTextFile {
            inherit
              name
              meta
              passthru
              derivationArgs
              ;
            executable = true;
            destination = "/bin/${name}";
            allowSubstitutes = true;
            preferLocalBuild = false;
            text =
              ''
                #!${shell}
                ${lib.concatMapStringsSep "\n" (option: "set -o ${option}") bashOptions}
              ''
              + lib.optionalString (runtimeEnv != null) (
                lib.concatStrings (
                  lib.mapAttrsToList (name: value: ''
                    ${lib.toShellVar name value}
                    export ${name}
                  '') runtimeEnv
                )
              )
              + lib.optionalString (runtimeInputs != [ ]) ''

                export PATH="${lib.makeBinPath runtimeInputs}${lib.optionalString inheritPath ":$PATH"}"
              ''
              + ''

                ${text}
              '';

            checkPhase =
              # GHC (=> shellcheck) isn't supported on some platforms (such as risc-v)
              # but we still want to use writeShellApplication on those platforms
              let
                shellcheckSupported =
                  lib.meta.availableOn stdenv.buildPlatform shellcheck-minimal.compiler
                  && (builtins.tryEval shellcheck-minimal.compiler.outPath).success;
                excludeFlags = lib.optionals (excludeShellChecks != [ ]) [
                  "--exclude"
                  (lib.concatStringsSep "," excludeShellChecks)
                ];
                shellcheckCommand = lib.optionalString shellcheckSupported ''
                  # use shellcheck which does not include docs
                  # pandoc takes long to build and documentation isn't needed for just running the cli
                  ${lib.getExe shellcheck-minimal} ${
                    lib.escapeShellArgs (excludeFlags ++ extraShellCheckFlags)
                  } "$target"
                '';
              in
              if checkPhase == null then
                ''
                  runHook preCheck
                  ${stdenv.shellDryRun} "$target"
                  ${shellcheckCommand}
                  runHook postCheck
                ''
              else
                checkPhase;
          };

        screenshot-save = pkgs.writeShellApplication {
          name = "screenshot-save";
          runtimeInputs = with pkgs; [
            busybox
            maim
            libnotify
          ];
          text = ''
            FILENAME="$(date +%s).png"
            maim --hidecursor -s /home/a/Pictures/"$FILENAME"
            notify-send "Screenshot saved ($FILENAME)"
          '';
        };

        screenshot-copy = pkgs.writeShellApplication {
          name = "screenshot-copy";
          runtimeInputs = with pkgs; [
            maim
            libnotify
            xclip
          ];
          text = ''
            maim --hidecursor -s | xclip -selection clipboard -t image/png
            notify-send "Screenshot copied"
          '';
        };

        system-rebuild = writeWithShellApplication {
          name = "system-rebuild";
          shell = "${pkgs.bash}/bin/bash -i";
          runtimeInputs = with pkgs; [
            figlet
            coreutils
            nh
          ];
          text = ''
            figlet "#$HOSTNAME"

            read -r -p "Config source [Remote (default), Local]: " config_source
            config_source=''${config_source:-Github}
            case "$config_source" in
              [Rr]|[Rr]emote)
                read -r -e -p "Remote path to config: " config_path
                read -r -p "Build and activate the new configuration? [Yes (default), No]: " build_and_activate
                build_and_activate=''${build_and_activate:-Yes}
                case "$build_and_activate" in
                  [Yy]|[Yy]es)
                    nh os switch "$config_path"
                    ;;
                  [Nn]|[Nn]o)
                    ;;
                esac
                ;;
              [Ll]|[Ll]ocal)
                read -r -e -p "Local path to config: " config_path
                if [[ "$config_path" == ~* ]]; then
                  config_path="''${config_path/#\~/$HOME}"
                fi
                config_path="$(realpath "$config_path")" # TODO maybe remove

                read -r -p "Update flake inputs? [No (default), All, Select, List]: " update_flake
                update_flake=''${update_flake:-No}
                case "$update_flake" in
                  [Nn]|[Nn]o)
                    ;;
                  [Aa]|[Aa]ll)
                    nix flake update --flake "$config_path"
                    ;;
                  [Ss]|[Ss]elect)
                    echo "TODO use locker"
                    exit 1
                    ;;
                  [Ll]|[Ll]ist)
                    read -r -p "Inputs list separated by spaces (e.g nixpkgs home-manager dwm): " flake_inputs
                    nix flake update "$flake_inputs" --flake "$config_path"
                    ;;
                esac

                read -r -p "Build and activate the new configuration? [Yes (default), No]: " build_and_activate
                build_and_activate=''${build_and_activate:-Yes}
                case "$build_and_activate" in
                  [Yy]|[Yy]es)
                    nh os switch "$config_path"
                    ;;
                  [Nn]|[Nn]o)
                    ;;
                esac

                read -r -p "Commit and push? [No (default), Yes]: " commit_and_push
                commit_and_push=''${commit_and_push:-No}
                case "$commit_and_push" in
                  [Nn]|[Nn]o)
                    ;;
                  [Yy]|[Yy]es)
                    git -C "$config_path" fetch
                    git -C "$config_path" diff -U0 main origin/main
                    git -C "$config_path" add -A

                    read -r -p "Commit message (current datetime by default): " commit_message
                    commit_message="''${commit_message:-$(date '+%Y-%m-%d %H:%M:%S')}"

                    git -C "$config_path" commit -m "$commit_message"
                    git -C "$config_path" push -u origin
                    ;;
                esac
                ;;
              *)
                echo "Invalid config source" >&2
                exit 1
                ;;
            esac
          '';
        };
      in
      {
        packages = {
          inherit
            screenshot-save
            screenshot-copy
            system-rebuild
            ;

          default = pkgs.symlinkJoin {
            name = "useful-scripts";
            paths = [
              screenshot-save
              screenshot-copy
              system-rebuild
            ];
          };
        };
      }
    );
}
