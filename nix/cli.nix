{ config, lib, pkgs, ... }:

with pkgs;
with lib;
with builtins;

let

  cfg = config.cli;

  compleat = haskellPackages.callPackage (
    { mkDerivation, base, directory, parsec, process, stdenv, unix }:
    mkDerivation {
      pname = "compleat";
      version = "1.0";
      src = fetchFromGitHub {
        owner = "mbrubeck";
        repo = "compleat";
        rev = "905b779592f701b037fa500ee891f7be3d8bd2c3";
        sha256 = "03mis6lpszfaj463pgcwk58cxhsw5i965sv923q6k2jw4lrk78cq";
      };
      isLibrary = false;
      isExecutable = true;
      executableHaskellDepends = [ base directory parsec process unix ];
      license = stdenv.lib.licenses.mit;
    }
  ) {};

  completionsFile = writeText "commands.compleat" (
    concatStringsSep "; " (
      concatMap (cmd: cmd.completions) (attrValues cfg.commands)
    )
  );

  stepOpts = {name, config, ... }: {
    options = {
      binary = mkOption {
        type = with types; nullOr path;
        default = null;
      };
      dependencies = mkOption {
        type = with types; listOf str;
        default = [];
      };
      interactive = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  mkSub = name: subCommands: writeScriptBin name ''
    #!${stdenv.shell}

    case "$1" in
    ${concatStrings (mapAttrsToList (cmd: sub: optionalString (sub.binary != null) ''
      ${cmd})
        shift 1
        exec "${sub.binary}" "$@"
        ;;
    '') subCommands)}
    *)
      echo >&2 "Unknown sub command $1"
      exit 1
      ;;
    esac
  '';

  safeName = replaceStrings [":" " " "/"] ["_" "_" "_"];

  makefile = name: steps:
    writeText "Makefile" (concatStrings (
      mapAttrsToList (stepName: step: let target = safeName stepName; in ''
        .PHONY${optionalString step.interactive " .NOTPARALLEL"}: ${target}
        ${target}: ${toString (map safeName step.dependencies)}
        ''\t@echo >&2 "> ${name}:${stepName}"
        ${if step.binary == null then "" else "\t@${step.binary} $(cmdargs)"}
      '') steps ++ singleton ''
        all: ${toString (map safeName (attrNames steps))}
      ''
    ));

  mkSteps = name: bin: maxjobs: steps:
    (if bin then writeScriptBin else writeScript) (safeName name) ''
      #!${stdenv.shell}
      exec ${gnumake}/bin/make cmdargs="$*" -j ${toString maxjobs} \
        --no-print-directory -f ${makefile name steps} all
    '';

  subCmdOpts = parentName: { name, config, ... }: {
    options = {
      binary = mkOption {
        type = with types; nullOr path;
        default = null;
      };
      steps = mkOption {
        type = with types; attrsOf (submodule stepOpts);
        default = {};
      };
      maxParallelism = mkOption {
        type = with types; nullOr int;
        default = null;
      };
      completions = mkOption {
        type = with types; listOf str;
        default = [];
      };
    };
    config = {
      binary = mkIf (config.steps != {}) (
        mkSteps "${parentName}:${name}" false config.maxParallelism config.steps
      );
    };
  };

  commandOpts = { name, config, ... }: {
    options = {
      subCommands = mkOption {
        type = with types; attrsOf (submodule (subCmdOpts name));
        default = {};
      };

      steps = mkOption {
        type = with types; attrsOf (submodule stepOpts);
        default = {};
      };

      maxParallelism = mkOption {
        type = with types; nullOr int;
        default = null;
      };

      package = mkOption {
        type = types.package;
        default = with config; (
          if subCommands == {} && steps == {} then
            throw "The command ${name} has no sub commands or steps defined"
          else if subCommands != {} && steps != {} then
            throw "The command ${name} has both sub commands and steps defined"
          else if subCommands != {} then mkSub name subCommands
          else mkSteps name true config.maxParallelism steps
        );
      };

      completions = mkOption {
        type = with types; listOf str;
        default = [];
      };
    };

    config = {
      completions = concatLists (mapAttrsToList (cmd: sub:
        if sub.completions == [] then [ "${name} ${cmd}" ]
        else map (c: "${name} ${cmd} (${c})") (filter (c: c != "") sub.completions)
      ) config.subCommands);
    };
  };

in {
  imports = [
    ./assertions.nix
  ];

  options = {
    cli = {
      build.bashrc = mkOption {
        type = types.package;
      };

      build.bootstrapScript = mkOption {
        type = types.package;
      };

      shell = {
        bootstrapScript = mkOption {
          type = types.lines;
          default = "";
        };
        shellHook = mkOption {
          type = types.lines;
          default = "";
        };
        path = mkOption {
          type = with types; listOf package;
          default = [];
        };
        environment = mkOption {
          type = types.attrs;
          default = {};
        };
      };

      commands = mkOption {
        type = with types; attrsOf (submodule commandOpts);
        default = {};
      };
    };
  };

  config = {
    cli.shell.environment.PATH = "${makeBinPath cfg.shell.path}:$PATH";

    cli.shell.path = map (cmd: cmd.package) (attrValues cfg.commands);

    cli.build.bashrc = config.withAssertions (writeText "bashrc" ''
      ${concatStrings (mapAttrsToList (k: v: ''
        export ${k}="${toString v}"
      '') cfg.shell.environment)}
      ${cfg.shell.shellHook}
    '');

    cli.build.bootstrapScript = writeScript "bootstrap.sh" ''
      #!${stdenv.shell}
      ${cfg.shell.bootstrapScript}
    '';

    cli.shell.shellHook = ''
      if [ -n "$RELOADER_PID" ]; then
        reload() {
          kill -1 "$RELOADER_PID"
          exit &>/dev/null
        }
      fi

      _run_compleat() {
        export COMP_POINT COMP_CWORD COMP_WORDS COMPREPLY BASH_VERSINFO COMP_LINE
        ${compleat}/bin/compleat "$@"
      }

      if [ -s "${completionsFile}" ]; then
        for COMMAND in `${compleat}/bin/compleat ${completionsFile}`; do
          complete -o nospace -o default \
            -C "_run_compleat ${completionsFile} $COMMAND" $COMMAND
        done
      fi
    '';
  };
}
