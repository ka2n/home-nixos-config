{ config, pkgs, lib, inputs, modulesPath, ... }:

let
  # Custom packages
  e2m-hass-bridge = pkgs.callPackage ./pkgs/e2m-hass-bridge/package.nix {};

  # e2m-hass-bridge device configuration override
  # カスタマイズガイド: docs/e2m-hass-bridge-customization.md
  # 元の設定: external-docs/e2m-hass-bridge/src/deviceConfig.ts
  #
  # メーカーコード検索: https://echonet-lite.ka2n.dev/
  #   主要メーカー: 000009=Panasonic, 000005=Sharp, 00000e=Daikin, 000011=Mitsubishi
  #
  # マージルール:
  #   - オブジェクト: 再帰的にマージ（部分的な変更が可能）
  #   - 配列: 完全置換（元の値も含めて全て記述する必要あり）
  #   - 未指定のキー: 元の設定を保持
  e2m-hass-bridge-device-config = pkgs.writeText "e2m-device-config.json" (builtins.toJSON {
    # Panasonic Eolia エアコンの設定
    "000009" = {
      # 温度範囲の変更
      override = {
        composite = {
          climate = {
            min_temp = 18;  # デフォルト: 16
            max_temp = 28;  # デフォルト: 30
          };
        };
      };
      # 定期的にリクエストするプロパティ（配列は完全置換される）
      autoRequestProperties = {
        homeAirConditioner = [
          "operationStatus"
          "operationMode"
          "targetTemperature"
          "airFlowLevel"
          "airFlowDirectionVertical"
          "automaticControlAirFlowDirection"
          "roomTemperature"
          "humidity"
        ];
        electricWaterHeater = [ "remainingWater" ];
      };
      # ファンモードマッピング（Home Assistant ⇔ ECHONET Lite）
      climate = {
        fanmodeMapping = {
          # Home Assistant → ECHONET Lite
          command = {
            auto = "auto";
            "1" = "2";
            "2" = "3";
            "3" = "4";
            "4" = "6";
          };
          # ECHONET Lite → Home Assistant
          state = {
            auto = "auto";
            "1" = "1";
            "2" = "1";
            "3" = "2";
            "4" = "3";
            "5" = "3";
            "6" = "4";
            "7" = "4";
            "8" = "4";
          };
        };
      };
    };

    # 複数メーカーの設定例（コメントアウト）
    # "000005" = {  # Sharp
    #   override.composite.climate = {
    #     min_temp = 17;
    #     max_temp = 32;
    #   };
    # };
    # "00000e" = {  # Daikin
    #   override.composite.climate = {
    #     min_temp = 16;
    #     max_temp = 31;
    #   };
    # };
  });
in
{
  imports = [
    ./hardware-configuration.nix
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
  ];

  # Proxmox LXC specific options
  proxmoxLXC = {
    manageNetwork = false;   # ネットワークはProxmoxで管理
    manageHostName = true;   # ホスト名はNixで管理
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
        1883   # MQTT (Mosquitto)
        8080   # zigbee2mqtt frontend
        8482   # home-assistant-matter-hub UI
        3000   # echonetlite2mqtt UI
        3001   # e2m-hass-bridge UI
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

    # Enable mDNS reflection for LXC containers
    reflector = true;
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
      mqtt-homeassistant-password = {
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

      # e2m-hass-bridge
      mqtt-e2m-hass-bridge-password = {
        owner = "mosquitto";
        group = "mosquitto";
      };
      e2m-hass-bridge-env = {
        format = "dotenv";
        sopsFile = ./secrets/e2m-hass-bridge.env;
      };
    };
  };

  # MQTT Broker
  services.mosquitto = {
    enable = true;
    listeners = [{
      address = "0.0.0.0";
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
        homeassistant = {
          acl = [ "readwrite #" ];
          passwordFile = config.sops.secrets.mqtt-homeassistant-password.path;
        };
        e2m-hass-bridge = {
          acl = [ "readwrite #" ];
          passwordFile = config.sops.secrets.mqtt-e2m-hass-bridge-password.path;
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

  # e2m-hass-bridge service
  systemd.services.e2m-hass-bridge = {
    description = "Bridge between echonetlite2mqtt and Home Assistant";
    after = [ "network.target" "mosquitto.service" ];
    wants = [ "mosquitto.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      MQTT_BROKER = "mqtt://localhost:1883";
      MQTT_USERNAME = "e2m-hass-bridge";
      ECHONETLITE2MQTT_BASE_TOPIC = "echonetlite2mqtt/elapi/v2/devices";
      HA_DISCOVERY_PREFIX = "homeassistant";
      PORT = "3001";
      LOG_LEVEL = "info";
      DESCRIPTION_LANGUAGE = "ja";
      MQTT_TASK_INTERVAL = "100";
      AUTO_REQUEST_INTERVAL = "180000";
      DEVICE_CONFIG_OVERRIDE_PATH = "${e2m-hass-bridge-device-config}";
    };

    serviceConfig = {
      EnvironmentFile = config.sops.secrets.e2m-hass-bridge-env.path;
      Type = "simple";
      ExecStart = "${e2m-hass-bridge}/bin/e2m-hass-bridge";
      Restart = "always";
      RestartSec = "10s";

      DynamicUser = true;
      StateDirectory = "e2m-hass-bridge";
      WorkingDirectory = "/var/lib/e2m-hass-bridge";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/e2m-hass-bridge" ];
      PrivateNetwork = false;

      StandardOutput = "journal";
      StandardError = "journal";
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
