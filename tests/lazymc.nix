{ testers, outputs }:

testers.nixosTest {
  name = "lazymc";
  nodes.server =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      imports = [
        outputs.nixosModules.minecraft-servers
        outputs.nixosModules.minecraft-lazymc
      ];

      services.minecraft-servers = {
        enable = true;
        eula = true;
        servers.test = {
          enable = true;
          jvmOpts = "-Xmx512M";
          package = pkgs.vanilla-server;
          serverProperties = {
            server-port = 25566; # Internal port
            level-type = "flat";
          };
          openFirewall = false;
        };
      };

      services.minecraft-lazymc.servers.test = {
        enable = true;
        publicAddress = "0.0.0.0:25565";
        openFirewall = true;
        extraConfig = {
          time.sleep_after = 60;
        };
      };
    };

  testScript =
    { nodes, ... }:
    ''
      name = "test"

      # lazymc service should start
      server.wait_for_unit(f"minecraft-lazymc-{name}.service")

      # lazymc should be listening on the public port
      server.wait_for_open_port(25565)

      # lazymc.toml should be generated
      server.succeed(f"test -f /srv/minecraft/{name}/lazymc.toml")

      # Verify lazymc.toml has correct content
      server.succeed(f"grep 'address = \"0.0.0.0:25565\"' /srv/minecraft/{name}/lazymc.toml")
      server.succeed(f"grep 'address = \"127.0.0.1:25566\"' /srv/minecraft/{name}/lazymc.toml")

      # The core minecraft service should NOT be running (lazymc manages it)
      server.fail(f"systemctl is-active minecraft-server-{name}.service")
    '';
}
