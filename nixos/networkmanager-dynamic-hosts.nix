{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.networking.networkmanager.dynamichosts;

  enable = config.networking.networkmanager.enable && cfg.enable &&
    cfg.hostsDirs != {};

in {
  options = {
    networking.networkmanager.dynamichosts = {
      enable = mkOption {
        type = types.bool;
        default = false;
      };
      hostsDirs = mkOption {
        type = with types; attrsOf (submodule {
          options = {
            user = mkOption {
              type = types.str;
              default = "root";
            };
            group = mkOption {
              type = types.str;
              default = "root";
            };
          };
        });
        default = {};
      };
    };
  };

  config = mkIf enable {

    networking.networkmanager.useDnsmasq = true;

    systemd.services.nm-setup-hostsdirs = {
      wantedBy = [ "network-manager.service" ];
      before = [ "network-manager.service" ];
      partOf = [ "network-manager.service" ];
      script = concatStrings (mapAttrsToList (n: d: ''
        mkdir -p "/run/nm-hostsdirs/${n}"
        chown "${d.user}:${d.group}" "/run/nm-hostsdirs/${n}"
        chmod 0775 "/run/nm-hostsdirs/${n}"
      '') cfg.hostsDirs);
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExist = true;
      };
    };

    environment.etc = {
      "NetworkManager/dnsmasq.d/dyndns.conf".text = concatMapStrings (n: ''
        hostsdir=/run/nm-hostsdirs/${n}
      '') (attrNames cfg.hostsDirs);
    };

  };
}
