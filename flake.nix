{
  description = "A bunch of useful scripts";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    wallpapers = {
      url = "github:mow44/wallpapers/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    locker = {
      url = "github:mow44/locker/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    uxn11 = {
      url = "github:mow44/uxn11/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    dexe = {
      url = "github:mow44/dexe/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    catclock = {
      url = "github:mow44/catclock/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    calendar = {
      url = "github:mow44/calendar/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    donsol = {
      url = "github:mow44/donsol/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    noodle = {
      url = "github:mow44/noodle/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };

    dmenu = {
      url = "github:mow44/dmenu/main";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      wallpapers,
      locker,
      uxn11,
      dexe,
      catclock,
      calendar,
      donsol,
      noodle,
      dmenu,
      ...
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
      in
      {
        packages = rec {
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
              git
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

                  read -r -p "Generate hardware config? [Yes (default), No]: " hardware_config
                  hardware_config=''${hardware_config:-Yes}
                  case "$hardware_config" in
                    [Yy]|[Yy]es)
                      sudo nixos-generate-config --show-hardware-config | tee "$config_path"/hardware-configuration.nix
                      ;;
                    [Nn]|[Nn]o)
                      ;;
                  esac

                  read -r -p "Update flake inputs? [No (default), All, Select, List]: " update_flake
                  update_flake=''${update_flake:-No}
                  case "$update_flake" in
                    [Nn]|[Nn]o)
                      ;;
                    [Aa]|[Aa]ll)
                      nix flake update --flake "$config_path"
                      ;;
                    [Ss]|[Ss]elect)
                      ${update-flake}/bin/update-flake "$config_path"
                      ;;
                    [Ll]|[Ll]ist)
                      read -r -p "Inputs list separated by spaces (e.g nixpkgs home-manager dwm): " raw_flake_inputs
                      read -r -a flake_inputs <<< "$raw_flake_inputs"
                      nix flake update "''${flake_inputs[@]}" --flake "$config_path"
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

          powermenu =
            let
              _dmenu = dmenu.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "powermenu";
              runtimeInputs = [
                _dmenu
                pkgs.coreutils
                pkgs.systemd
              ];
              text = ''
                option=$(echo -e "Shutdown\nReboot" | dmenu -i)
                case "$option" in
                  Shutdown)
                    systemctl poweroff
                    ;;
                  Reboot)
                    systemctl reboot
                    ;;
                esac
              '';
            };

          uxn11-dexe =
            let
              _uxn11 = uxn11.packages.${system}.default;
              _dexe = dexe.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "uxn11-dexe";
              runtimeInputs = [
                pkgs.util-linux
                _uxn11
              ];
              text = ''
                if [ $# -lt 1 ]; then
                  echo "Usage: uxn11-dexe <filepath>"
                  exit 1
                fi

                filepath="$1"

                if [ ! -f "$filepath" ]; then
                  echo "Error: File '$filepath' not found"
                  exit 1
                fi

                # NOTE script provides a proper pseudo-terminal to uxn11 for low cpu usage
                script -q -c "uxn11 ${_dexe}/bin/dexe.rom $filepath" /dev/null
              '';
            };

          uxn11-catclock =
            let
              _uxn11 = uxn11.packages.${system}.default;
              _catclock = catclock.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "uxn11-catclock";
              runtimeInputs = [
                pkgs.util-linux
                _uxn11
              ];
              text = ''
                script -q -c "uxn11 ${_catclock}/bin/catclock.rom" /dev/null
              '';
            };

          uxn11-calendar =
            let
              _uxn11 = uxn11.packages.${system}.default;
              _calendar = calendar.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "uxn11-calendar";
              runtimeInputs = [
                pkgs.util-linux
                _uxn11
              ];
              text = ''
                script -q -c "uxn11 ${_calendar}/bin/calendar.rom" /dev/null
              '';
            };

          uxn11-donsol =
            let
              _uxn11 = uxn11.packages.${system}.default;
              _donsol = donsol.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "uxn11-donsol";
              runtimeInputs = [
                pkgs.util-linux
                _uxn11
              ];
              text = ''
                script -q -c "uxn11 ${_donsol}/bin/donsol.rom" /dev/null
              '';
            };

          uxn11-noodle =
            let
              _uxn11 = uxn11.packages.${system}.default;
              _noodle = noodle.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "uxn11-noodle";
              runtimeInputs = [
                pkgs.util-linux
                _uxn11
              ];
              text = ''
                if [ $# -ge 1 ]; then
                  filepath="$1"
                else
                  filepath=""
                fi

                script -q -c "uxn11 ${_noodle}/bin/noodle.rom $filepath" /dev/null
              '';
            };

          set-wallpaper =
            let
              _wallpapers = wallpapers.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "set-wallpaper";
              runtimeInputs = with pkgs; [
                hsetroot
                busybox
              ];
              text = ''
                if [ $# -ge 1 ]; then
                  filepath="$1"
                  if [ ! -f "$filepath" ]; then
                    echo "Error: File '$filepath' not found"
                    exit 1
                  fi
                else
                  filepath="$(find ${_wallpapers} \( -type f -o -type l \) | shuf -n 1)"
                fi

                hsetroot -fill "$filepath"
              '';
            };

          update-flake =
            let
              _locker = locker.packages.${system}.default;
            in
            pkgs.writeShellApplication {
              name = "update-flake";
              runtimeInputs = [
                pkgs.coreutils
                _locker
              ];
              text = ''
                if [ $# -ge 1 ]; then
                  directory="$1"
                else
                  directory="$PWD"
                fi

                if [ ! -f "$directory/flake.lock" ]; then
                  echo "Error: File '$directory/flake.lock' not found"
                  exit 1
                fi

                mapfile -t flake_inputs < <(locker "$directory/flake.lock" -d=100)

                if [[ ''${#flake_inputs[@]} -eq 0 ]]; then
                  echo "No inputs provided"
                else
                  nix flake update "''${flake_inputs[@]}" --flake "$directory"
                fi
              '';
            };

          default = pkgs.symlinkJoin {
            name = "useful-scripts";
            paths = [
              screenshot-save
              screenshot-copy
              system-rebuild
              powermenu
              uxn11-dexe
              uxn11-catclock
              uxn11-calendar
              uxn11-donsol
              uxn11-noodle
              set-wallpaper
              update-flake
            ];
          };
        };

      }
    );
}
