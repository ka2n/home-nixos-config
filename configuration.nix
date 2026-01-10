{ config, pkgs, lib, inputs, modulesPath, ... }:

{
  imports = [
    ./hardware-configuration.nix
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  # Proxmox LXC specific options
  proxmoxLXC = {
    manageNetwork = true;    # ネットワークはNixで管理
    manageHostName = true;   # ホスト名もNixで管理
  };

  # System basics
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;  # LXC doesn't need bootloader

  # LXC container specific - suppress kernel filesystem mounts
  systemd.suppressedSystemUnits = [
    "dev-mqueue.mount"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
  ];

  networking.hostName = "sensors";

  # Timezone and locale
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";

  # Network configuration
  networking = {
    enableIPv6 = true;  # Required for Matter protocol
    firewall = {
      enable = true;
      allowedTCPPorts = [
        8080   # zigbee2mqtt frontend
        8482   # home-assistant-matter-hub UI
        3000   # echonetlite2mqtt UI
        5540   # Matter bridge (primary)
      ];
      allowedUDPPorts = [
        3610   # ECHONET Lite standard port
        5353   # mDNS
      ];
    };
  };

  # mDNS (required for Matter device discovery)
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
    openFirewall = true;
  };

  # Secrets management with sops-nix
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets = {
      # mosquitto/zigbee2mqtt
      mqtt-zigbee2mqtt-password = {
        owner = "zigbee2mqtt";
        group = "zigbee2mqtt";
      };
      mqtt-echonetlite2mqtt-password = {
        owner = "mosquitto";
        group = "mosquitto";
      };
      zigbee-network-key = {
        owner = "zigbee2mqtt";
        group = "zigbee2mqtt";
      };

      # OCI container environment files
      echonetlite2mqtt-env = {
        format = "dotenv";
        sopsFile = ./secrets/echonetlite2mqtt.env;
      };
      home-assistant-matter-hub-env = {
        format = "dotenv";
        sopsFile = ./secrets/home-assistant-matter-hub.env;
      };
    };
  };

  # MQTT Broker
  services.mosquitto = {
    enable = true;
    listeners = [{
      address = "127.0.0.1";
      port = 1883;
      users = {
        zigbee2mqtt = {
          acl = [ "readwrite #" ];
          passwordFile = config.sops.secrets.mqtt-zigbee2mqtt-password.path;
        };
        echonetlite2mqtt = {
          acl = [ "readwrite #" ];
          passwordFile = config.sops.secrets.mqtt-echonetlite2mqtt-password.path;
        };
      };
      settings = {
        allow_anonymous = false;
      };
    }];
  };

  # zigbee2mqtt service
  services.zigbee2mqtt = {
    enable = true;
    settings = {
      # Availability checking
      availability = {
        active.timeout = 5;
        passive.timeout = 1500;
      };

      mqtt = {
        server = "mqtt://localhost:1883";
        user = "zigbee2mqtt";
        password = "!secret mqtt_password";
      };

      serial = {
        port = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_da0e4f7857c9eb119dfb8f4f1d69213e-if00-port0";
        adapter = "zstack";
        disable_led = true;
      };

      frontend = {
        port = 8080;
        host = "0.0.0.0";
      };

      advanced = {
        network_key = "!secret network_key";
        channel = 15;
        pan_id = 6754;  # Existing network PAN ID
        last_seen = "ISO_8601";
      };

      # Home Assistant integration
      homeassistant.enabled = true;
    };
  };

  # Setup Zigbee USB device permissions (runs as root before zigbee2mqtt)
  systemd.services.zigbee-usb-permissions = {
    description = "Setup Zigbee USB device permissions";
    wantedBy = [ "multi-user.target" ];
    before = [ "zigbee2mqtt.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/chown zigbee2mqtt:zigbee2mqtt /dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_da0e4f7857c9eb119dfb8f4f1d69213e-if00-port0";
    };
  };

  # Create secret.yaml for zigbee2mqtt from sops secrets
  systemd.services.zigbee2mqtt = {
    preStart = ''
      # Convert hex string network key to array format
      NETWORK_KEY_HEX=$(cat ${config.sops.secrets.zigbee-network-key.path})
      NETWORK_KEY_ARRAY="["
      for i in $(seq 0 2 30); do
        BYTE="0x''${NETWORK_KEY_HEX:$i:2}"
        NETWORK_KEY_ARRAY="$NETWORK_KEY_ARRAY$((16#''${NETWORK_KEY_HEX:$i:2}))"
        if [ $i -lt 30 ]; then
          NETWORK_KEY_ARRAY="$NETWORK_KEY_ARRAY, "
        fi
      done
      NETWORK_KEY_ARRAY="$NETWORK_KEY_ARRAY]"

      cat > /var/lib/zigbee2mqtt/secret.yaml <<EOF
      mqtt_password: $(cat ${config.sops.secrets.mqtt-zigbee2mqtt-password.path})
      network_key: $NETWORK_KEY_ARRAY
      EOF
    '';
  };

  # OCI Containers setup
  virtualisation.oci-containers = {
    backend = "docker";

    containers = {
      # echonetlite2mqtt
      echonetlite2mqtt = {
        image = "banban525/echonetlite2mqtt:latest";
        autoStart = true;

        # host network mode required for ECHONET Lite UDP multicast
        extraOptions = [ "--network=host" ];

        environment = {
          MQTT_BROKER = "mqtt://localhost:1883";
          MQTT_USERNAME = "echonetlite2mqtt";
          ECHONET_TARGET_NETWORK = "192.168.50.0/24";
          REST_API_PORT = "3000";
        };

        environmentFiles = [
          config.sops.secrets.echonetlite2mqtt-env.path
        ];

        volumes = [
          "/var/lib/echonetlite2mqtt:/data"
        ];
      };

      # home-assistant-matter-hub
      home-assistant-matter-hub = {
        image = "ghcr.io/t0bst4r/home-assistant-matter-hub:latest";
        autoStart = true;

        # host network mode required for Matter/mDNS
        extraOptions = [ "--network=host" ];

        environment = {
          HAMH_HOME_ASSISTANT_URL = "http://192.168.50.201:8123";
          HAMH_HTTP_PORT = "8482";
          HAMH_LOG_LEVEL = "info";
        };

        environmentFiles = [
          config.sops.secrets.home-assistant-matter-hub-env.path
        ];

        volumes = [
          "/var/lib/home-assistant-matter-hub:/data"
        ];
      };
    };
  };

  # Docker daemon
  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      registry-mirrors = [ "https://mirror.gcr.io" ];
    };
  };

  # System packages
  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    mosquitto  # For mosquitto_pub/sub tools
    age        # For sops-nix
    sops
  ];

  # Tailscale
  services.tailscale.enable = true;

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
    };
  };

  system.stateVersion = "25.11"; # Did you read the comment?
}
