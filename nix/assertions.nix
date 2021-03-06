# Copied from NixOS

{ config, lib, pkgs, ... }:

with lib;

{

  options = {

    assertions = mkOption {
      type = types.listOf types.unspecified;
      default = [];
      example = [ { assertion = false; message = "you can't enable this for that reason"; } ];
      description = ''
        This option allows modules to express conditions that must
        hold for the evaluation of the system configuration to
        succeed, along with associated error messages for the user.
      '';
    };

    warnings = mkOption {
      default = [];
      type = types.listOf types.str;
      example = [ "The `foo' service is deprecated and will go away soon!" ];
      description = ''
        This option allows modules to show warnings to users during
        the evaluation of the system configuration.
      '';
    };

    withAssertions = mkOption {
      type = types.unspecified;
    };

  };

  config = {

    withAssertions = x:
      let
        failed = map (x: x.message) (filter (x: !x.assertion) config.assertions);
        showWarnings = res: fold (w: x:
          builtins.trace "[1;31mwarning: ${w}[0m" x
        ) res config.warnings;
      in showWarnings (
        if [] == failed then x
        else throw "\nFailed assertions:\n${concatStringsSep "\n" (map (x: "- ${x}") failed)}"
      );

  };

}
