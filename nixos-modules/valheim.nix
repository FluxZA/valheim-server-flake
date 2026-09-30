{
  self,
  steam-fetcher,
}: {
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.valheim;
  stateDir = "/var/lib/valheim";
in {
  options.services.valheim = {
    enable = lib.mkEnableOption (lib.mdDoc "Valheim Dedicated Server");

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${stateDir}";
      example = "/var/lib/valheim";
      description = lib.mdDoc "Absolude path to directory storing server data.";
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Some Cozy Server";
      description = lib.mdDoc "The name listed in the server browser.";
    };

    worldName = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "Midgard";
      description = lib.mdDoc ''
        The name of the world file to use, without the extension.
        If the world does not exist, then the server will generate a world from
        a random seed.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2456;
      description = lib.mdDoc ''
        The port on which to listen for incoming connections.

        Note that the port just above this one will be used for the Steam server browser service.
      '';
    };

    crossplay = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to enable cross-platform players.

        See the [announcement](https://steamcommunity.com/games/892970/announcements/detail/3308480236523722724)
        for details on this feature.

        This should be disabled when using a modded server that requires the
        client to be modded, as only PC versions can run mods.
      '';
    };

    noGraphics = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Whether to run with graphics or not.
        Enable this if you're headless with no GPU.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to open ports in the firewall.";
    };

    public = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = lib.mdDoc ''
        Toggles visibility on the Steam server & community lists.

        When not set, defaults to true (visible).
        Set to false to make the server private.
      '';
    };

    preset = lib.mkOption {
      type = with lib.types; nullOr (enum ["easy" "hard" "hardcore" "casual" "hammer" "immersive"]);
      default = null;
      example = "hardcore";
      description = lib.mdDoc ''
        The preset world modifier, valid options are
        "easy", "hard", "hardcore", "casual", "hammer" and "immersive".
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.str;
      default = "${stateDir}/password";
      description = lib.mdDoc ''
        File containing the server password.

        This is passed using systemd credentials.
      '';
    };

    adminList = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      example = [
        "72057602627862526"
        "72057602627862527"
      ];
      description = lib.mdDoc ''
        List of Steam IDs to be added to the adminlist.txt file.

        These users will have admin privileges on the server.
      '';
    };

    permittedList = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      example = [
        "72057602627862526"
        "72057602627862527"
      ];
      description = lib.mdDoc ''
        List of Steam IDs to be added to the permittedlist.txt file.

        Only these users will be allowed to join the server if the list is not empty.
        If you use this, all players not on the list will be unable to join.
      '';
    };

    bannedList = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      example = [
        "72057602627862526"
        "72057602627862527"
      ];
      description = lib.mdDoc ''
        List of Steam IDs to be added to the bannedlist.txt file.

        These users will be banned from the server.
      '';
    };

    numberBackups = lib.mkOption {
      type = lib.types.str;
      default = "4";
      description = lib.mdDoc ''Number of auto backups to keep. One uses shortDuration, the rest use longDuration.'';
    };

    backupShortDuration = lib.mkOption {
      type = lib.types.str;
      default = "7200";
      description = lib.mdDoc ''Duration in seconds after which the first auto backup is made.'';
    };

    backupLongDuration = lib.mkOption {
      type = lib.types.str;
      default = "43200";
      description = lib.mdDoc ''Duration in seconds between auto backups (ignoring the first).'';
    };

    saveInterval = lib.mkOption {
      type = lib.types.str;
      default = "1800";
      description = lib.mdDoc ''Duration in seconds between saves.'';
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [self.overlays.default steam-fetcher.overlay];

    users = {
      users.valheim = {
        isSystemUser = true;
        group = "valheim";
        home = cfg.stateDir;
        createHome = true;
      };
      groups.valheim = {};
    };

    systemd.services = let
      saveDir = "${cfg.stateDir}/saves";
      startScript = pkgs.writeShellScriptBin "valheim-start" ''
        exec ${pkgs.valheim-server}/bin/valheim-server \
              -name "${cfg.serverName}" \
              -batchmode \
              -savedir "${saveDir}" \
              -port "${toString cfg.port}" \
              -password $(cat "$CREDENTIALS_DIRECTORY/valheim-password") \
              -backups "${toString cfg.numberBackups}" \
              -backupshort "${toString cfg.backupShortDuration}" \
              -backuplong "${toString cfg.backupLongDuration}" \
              -saveinterval "${toString cfg.saveInterval}" \
              ${lib.optionalString (cfg.worldName != null) "-world \"${cfg.worldName}\""} \
              ${lib.optionalString cfg.crossplay "-crossplay"} \
              ${lib.optionalString (cfg.preset != null) "-preset \"${cfg.preset}\""} \
              ${lib.optionalString cfg.noGraphics "-nographics"} \
              -public ${
          if cfg.public
          then "1"
          else "0"
        }
      '';
    in {
      valheim = {
        description = "Valheim dedicated server";
        requires = ["network.target"];
        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        preStart = let
          createListFile = name: list: ''
            echo "// List of Steam IDs for ${name} ONE per line
            ${lib.strings.concatStringsSep "\n" list}" > ${saveDir}/${name}
            chown valheim:valheim ${saveDir}/${name}
          '';
        in ''
          mkdir -p ${saveDir}
          ${createListFile "adminlist.txt" cfg.adminList}
          ${createListFile "permittedlist.txt" cfg.permittedList}
          ${createListFile "bannedlist.txt" cfg.bannedList}
        '';

        serviceConfig = {
          Type = "exec";
          User = "valheim";
          ExecStart = "${startScript}/bin/valheim-start";
          # Hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = ["/"];
          ReadWritePaths = [
            "${cfg.stateDir}"
            "/tmp"
            "/var/tmp"
          ];
          LoadCredential = "valheim-password:${cfg.passwordFile}";
        };
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedUDPPorts = [
        cfg.port
        (cfg.port + 1) # Steam server browser
      ];
    };

    assertions = [
      {
        assertion = cfg.serverName != "";
        message = "The server name must not be empty.";
      }
      {
        assertion = cfg.worldName != "";
        message = "The world name must not be empty.";
      }
    ];
  };
}
