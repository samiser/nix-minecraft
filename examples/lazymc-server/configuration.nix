{ pkgs, ... }:
{
  # Base server configuration
  services.minecraft-servers = {
    enable = true;
    eula = true;

    # Secrets file for RCON password (create manually or manage with agenix/sops-nix)
    # Contents: RCON_PASSWORD=your-secret-password
    environmentFile = "/etc/minecraft-secrets";

    servers.paper = {
      enable = true;
      jvmOpts = "-Xmx4G -Xms2G";
      package = pkgs.paperServers.paper-1_21_4;

      serverProperties = {
        # Use a different internal port since lazymc uses 25565
        server-port = 25566;
        motd = "Server awake!";
        max-players = 20;
        # Enable RCON for remote console access
        enable-rcon = true;
        "rcon.port" = 25575;
        "rcon.password" = "@RCON_PASSWORD@"; # Substituted from environmentFile
      };

      # Don't open the internal port since lazymc handles public access
      openFirewall = false;
    };
  };

  # lazymc proxy configuration
  services.minecraft-lazymc.servers.paper = {
    enable = true;
    publicAddress = "0.0.0.0:25565";
    openFirewall = true;

    extraConfig = {
      # Server sleeps after 5 minutes of no players
      time.sleep_after = 300;

      # Custom MOTD when server is sleeping
      motd.sleeping = "Join to wake the sleeping server...";

      # RCON passthrough for remote console access
      rcon = {
        enabled = true;
        port = 25575;
        password = "@RCON_PASSWORD@"; # Substituted from environmentFile
      };
    };
  };
}
