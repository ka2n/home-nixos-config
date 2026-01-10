{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # System basics
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;  # LXC doesn't need bootloader

  # LXC container specific - disable kernel filesystem mounts
  boot.enableContainers = lib.mkForce false;
  systemd.mounts = lib.mkForce [];
  systemd.automounts = lib.mkForce [];

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
    age.keyFile = "/var/lib/sops-nix/key.txt";

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

  # Zigbee USB adapter udev rules
  services.udev.extraRules = ''
    # Sonoff Zigbee 3.0 USB Dongle Plus (CP210x)
    SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="zigbee", MODE="0660", GROUP="zigbee2mqtt"
  '';

  # zigbee2mqtt service
  services.zigbee2mqtt = {
    enable = true;
    settings = {
      mqtt = {
        server = "mqtt://localhost:1883";
        user = "zigbee2mqtt";
        password = "!secret mqtt_password";
      };
      serial = {
        port = "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_da0e4f7857c9eb119dfb8f4f1d69213e-if00-port0";
      };
      frontend = {
        port = 8080;
      };
      advanced = {
        network_key = "!secret network_key";
      };
    };
  };

  # Create secret.yaml for zigbee2mqtt from sops secrets
  systemd.services.zigbee2mqtt = {
    preStart = ''
      mkdir -p /var/lib/zigbee2mqtt
      cat > /var/lib/zigbee2mqtt/secret.yaml <<EOF
      mqtt_password: $(cat ${config.sops.secrets.mqtt-zigbee2mqtt-password.path})
      network_key: $(cat ${config.sops.secrets.zigbee-network-key.path})
      EOF
      chown zigbee2mqtt:zigbee2mqtt /var/lib/zigbee2mqtt/secret.yaml
      chmod 600 /var/lib/zigbee2mqtt/secret.yaml
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
