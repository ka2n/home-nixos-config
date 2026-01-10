# Home Automation NixOS Configuration - sensors

## サービス構成

- **mosquitto** - MQTT broker
- **zigbee2mqtt** - Zigbee to MQTT bridge
- **echonetlite2mqtt** - ECHONET Lite to MQTT bridge (Docker)
- **home-assistant-matter-hub** - Home Assistant to Matter bridge (Docker)

## ターゲット環境

- Proxmox LXC (x86_64)

## デプロイ手順

### 1. 設定をコピー

```bash
rsync -av --exclude='.git' --exclude='external-docs' ./ root@<target-ip>:/etc/nixos/
```

### 2. 適用

```bash
ssh root@<target-ip>
cd /etc/nixos
nixos-rebuild switch --flake .#sensors
```

### 3. 確認

```bash
systemctl status mosquitto zigbee2mqtt
docker ps
```

## Web UI

- zigbee2mqtt: http://target-ip:8080
- echonetlite2mqtt: http://target-ip:3000
- home-assistant-matter-hub: http://target-ip:8482

## Home Assistantトークン更新（後で）

```bash
# 開発マシンで
sops secrets/home-assistant-matter-hub.env
# PLACEHOLDER_TOKEN... を実際のトークンに置換して保存

# ターゲットマシンに反映
scp secrets/home-assistant-matter-hub.env root@<target-ip>:/etc/nixos/secrets/
ssh root@<target-ip> "cd /etc/nixos && nixos-rebuild switch --flake .#sensors"
```

## トラブルシューティング

### Zigbeeアダプターが見つからない
```bash
ls -l /dev/serial/by-id/
udevadm control --reload && udevadm trigger
```

### ECHONETデバイスが検出されない
```bash
docker logs echonetlite2mqtt
```

### Matterハブが接続できない
```bash
docker logs home-assistant-matter-hub
```
