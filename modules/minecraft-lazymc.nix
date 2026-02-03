{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.services.minecraft-lazymc;
  serversCfg = config.services.minecraft-servers;

  mkOpt' =
    type: default: description:
    mkOption { inherit type default description; };

  mkEnableOpt =
    description:
    mkOption {
      type = types.bool;
      default = false;
      example = true;
      inherit description;
    };

  parsePort = addr: toInt (last (splitString ":" addr));

  enabledServers = filterAttrs (_: conf: conf.enable) cfg.servers;

  getServerPort = name: serversCfg.servers.${name}.serverProperties.server-port or 25565;

  mkLazymcConfig =
    name: conf:
    let
      serverConf = serversCfg.servers.${name};
      serverPort = getServerPort name;
    in
    recursiveUpdate {
      public.address = conf.publicAddress;
      server = {
        command = "${getExe serverConf.package} ${serverConf.jvmOpts}";
        directory = ".";
        address = "127.0.0.1:${toString serverPort}";
      };
    } conf.extraConfig;
in
{
  options.services.minecraft-lazymc = {
    servers = mkOption {
      default = { };
      description = ''
        Servers to wrap with lazymc.
        Each entry corresponds to a server in <option>services.minecraft-servers.servers</option>.
      '';
      type = types.attrsOf (
        types.submodule (_: {
          options = {
            enable = mkEnableOption "lazymc proxy for this server";

            package = mkOption {
              type = types.package;
              default = pkgs.lazymc;
              defaultText = literalExpression "pkgs.lazymc";
              description = "The lazymc package to use.";
            };

            publicAddress = mkOpt' (types.strMatching "^[^:]+:[0-9]+$") "0.0.0.0:25565" ''
              Address for lazymc to listen on, in the format <literal>address:port</literal>.
            '';

            openFirewall = mkEnableOpt ''
              Whether to open the lazymc port in the firewall.
            '';

            extraConfig = mkOpt' types.attrs { } ''
              Extra lazymc.toml options, merged with the generated config.
              See <link xlink:href="https://github.com/timvisee/lazymc/blob/master/res/lazymc.toml"/>.
            '';
          };
        })
      );
    };
  };

  config = mkIf (enabledServers != { }) {
    assertions = [
      {
        assertion = serversCfg.enable;
        message = "services.minecraft-lazymc requires services.minecraft-servers.enable = true.";
      }
    ]
    ++ mapAttrsToList (name: _: {
      assertion = serversCfg.servers ? ${name};
      message = "lazymc server '${name}' does not exist in services.minecraft-servers.servers.";
    }) enabledServers
    ++ mapAttrsToList (name: _: {
      assertion = serversCfg.servers.${name}.enable or false;
      message = "lazymc server '${name}' is not enabled in services.minecraft-servers.servers.";
    }) enabledServers
    ++ mapAttrsToList (name: conf: {
      assertion = parsePort conf.publicAddress != getServerPort name;
      message = "lazymc server '${name}': publicAddress port must differ from server-port.";
    }) enabledServers
    ++ [
      (
        let
          ports = mapAttrsToList (_: conf: parsePort conf.publicAddress) enabledServers;
          duplicates = filter (p: count (x: x == p) ports > 1) (unique ports);
        in
        {
          assertion = duplicates == [ ];
          message = "Multiple lazymc servers have the same publicAddress port: ${toString duplicates}";
        }
      )
    ]
    ++ mapAttrsToList (name: _: {
      assertion = !(serversCfg.servers.${name}.openFirewall or false);
      message = "lazymc server '${name}': set openFirewall in lazymc config, not the core server config.";
    }) enabledServers;

    systemd.services =
      let
        coreOverrides = mapAttrs' (
          name: _:
          nameValuePair "minecraft-server-${name}" {
            wantedBy = mkForce [ ];
          }
        ) enabledServers;

        lazymcServices = mapAttrs' (
          name: conf:
          let
            serverConf = serversCfg.servers.${name};
            dataDir = "${serversCfg.dataDir}/${name}";

            lazymcToml = (pkgs.formats.toml { }).generate "lazymc.toml" (mkLazymcConfig name conf);

            coreService = config.systemd.services."minecraft-server-${name}";

            preStartScript = pkgs.writeShellApplication {
              name = "minecraft-lazymc-${name}-pre-start";
              text = ''
                ${coreService.serviceConfig.ExecStartPre}

                ln -sf ${lazymcToml} lazymc.toml
                echo lazymc.toml >> .nix-minecraft-managed
              '';
            };
          in
          nameValuePair "minecraft-lazymc-${name}" {
            description = "lazymc proxy for Minecraft Server ${name}";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];

            startLimitIntervalSec = 120;
            startLimitBurst = 5;

            serviceConfig = {
              Type = "simple";
              WorkingDirectory = dataDir;
              User = serversCfg.user;
              Group = serversCfg.group;
              EnvironmentFile = mkIf (serversCfg.environmentFile != null) (toString serversCfg.environmentFile);

              ExecStartPre = getExe preStartScript;
              ExecStart = "${getExe conf.package} start --config lazymc.toml";
              inherit (coreService.serviceConfig) ExecStopPost;

              TimeoutStopSec = "2min";
              Restart = "always";

              CapabilityBoundingSet = [ "" ];
              DeviceAllow = [ "" ];
              LockPersonality = true;
              PrivateDevices = true;
              PrivateTmp = true;
              PrivateUsers = true;
              ProtectClock = true;
              ProtectControlGroups = true;
              ProtectHome = true;
              ProtectHostname = true;
              ProtectKernelLogs = true;
              ProtectKernelModules = true;
              ProtectKernelTunables = true;
              ProtectProc = "invisible";
              RestrictAddressFamilies = [
                "AF_UNIX"
                "AF_INET"
                "AF_INET6"
              ];
              RestrictNamespaces = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              SystemCallArchitectures = "native";
              UMask = "0007";
            };

            inherit (serverConf) path environment;
          }
        ) enabledServers;
      in
      coreOverrides // lazymcServices;

    networking.firewall =
      let
        toOpen = filterAttrs (_: conf: conf.openFirewall) enabledServers;
        tcpPorts = mapAttrsToList (_: conf: parsePort conf.publicAddress) toOpen;
      in
      {
        allowedTCPPorts = tcpPorts;
      };
  };
}
