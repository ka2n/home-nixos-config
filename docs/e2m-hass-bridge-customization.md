# e2m-hass-bridge デバイス設定カスタマイズガイド

## 概要

e2m-hass-bridgeは、ECHONET Lite機器のメーカー固有設定をJSON形式で上書きできます。
NixOS設定内で`e2m-hass-bridge-device-config`を編集することで、温度範囲やファンモードなどをカスタマイズできます。

## 設定ファイルの場所

**configuration.nix** の `let` セクション内:
```nix
e2m-hass-bridge-device-config = pkgs.writeText "e2m-device-config.json" (builtins.toJSON {
  # ここにカスタマイズ設定を記述
});
```

## メーカーコード一覧

主要メーカーのコード（e2m-hass-bridge deviceConfig.tsより）:

| メーカー | コード |
|---------|-------|
| Panasonic (パナソニック) | `00000b` |
| Mitsubishi Electric (三菱電機) | `000006` |
| Fujitsu General (富士通ゼネラル) | `00008a` |
| Rinnai (リンナイ) | `000059` |
| Nature (Nature Remo) | `000106` |

完全なリストは`external-docs/e2m-hass-bridge/src/deviceConfig.ts`の`Manufacturer`定数または[ECHONET Lite検索サイト](https://echonet-lite.ka2n.dev/)で検索可能。

## 基本構造

```nix
"<メーカーコード>" = {
  override = {
    composite = {
      climate = { /* エアコン設定 */ };
    };
  };
  autoRequestProperties = {
    /* 定期リクエストするプロパティ */
  };
  climate = {
    fanmodeMapping = { /* ファンモードマッピング */ };
  };
};
```

## カスタマイズ例

### 1. 温度範囲の変更（最も一般的）

```nix
"00000b" = {  # Panasonic
  override.composite.climate = {
    min_temp = 18;  # デフォルト: 16
    max_temp = 28;  # デフォルト: 30
  };
};
```

### 2. 複数メーカーの設定

```nix
e2m-hass-bridge-device-config = pkgs.writeText "e2m-device-config.json" (builtins.toJSON {
  "00000b" = {  # Panasonic
    override.composite.climate = {
      min_temp = 18;
      max_temp = 28;
    };
  };
  "000006" = {  # Mitsubishi Electric
    override.composite.climate = {
      min_temp = 16;
      max_temp = 30;
    };
  };
});
```

### 3. 自動リクエストプロパティの変更

ECHONET Lite機器が自動で通知しないプロパティを定期的に取得:

```nix
"00000b" = {
  autoRequestProperties = {
    homeAirConditioner = [
      "operationStatus"
      "operationMode"
      "targetTemperature"
      "roomTemperature"
    ];
    electricWaterHeater = [
      "remainingWater"
    ];
  };
};
```

**注意**: 配列は完全置換されます。元の値を保持したい場合は全て記述してください。

### 4. ファンモードマッピングの変更

Home AssistantとECHONET Liteのファンモード値の変換:

```nix
"00000b" = {
  climate.fanmodeMapping = {
    command = {  # HA → ECHONET
      auto = "auto";
      "1" = "2";
      "2" = "3";
      "3" = "4";
      "4" = "6";
    };
    state = {    # ECHONET → HA
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
```

### 5. 完全な設定例

```nix
e2m-hass-bridge-device-config = pkgs.writeText "e2m-device-config.json" (builtins.toJSON {
  "00000b" = {  # Panasonic Eolia
    override = {
      composite = {
        climate = {
          min_temp = 18;
          max_temp = 28;
        };
      };
    };
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
      electricWaterHeater = [
        "remainingWater"
      ];
    };
    climate = {
      fanmodeMapping = {
        command = {
          auto = "auto";
          "1" = "2";
          "2" = "3";
          "3" = "4";
          "4" = "6";
        };
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
});
```

## マージの仕組み

### Deep Merge ルール

| 型 | 動作 |
|---|-----|
| **オブジェクト** | 再帰的にマージ（キーごとにマージ） |
| **配列** | **完全置換**（JSONの値で上書き） |
| **プリミティブ値** | 上書き |
| **未指定のキー** | 元の値を保持 |

### マージ例

**元の設定**:
```typescript
{
  override: { composite: { climate: { min_temp: 16, max_temp: 30 } } },
  autoRequestProperties: { homeAirConditioner: [...多数...] },
  climate: { fanmodeMapping: {...} },
}
```

**JSON Override**:
```nix
{
  override.composite.climate = { min_temp = 18; max_temp = 28; };
}
```

**結果**:
- `min_temp`, `max_temp`: **上書きされる**（18, 28）
- `autoRequestProperties`: **元のまま保持**
- `climate.fanmodeMapping`: **元のまま保持**

## デプロイ

設定変更後:

```bash
sudo nixos-rebuild switch --flake .#sensors
```

## 動作確認

```bash
# サービスログを確認
journalctl -u e2m-hass-bridge -f

# JSON設定が読み込まれたことを確認（起動時に表示）
# [deviceConfig] Loaded configuration override from: /nix/store/.../e2m-device-config.json
```

## トラブルシューティング

### 設定が反映されない

1. ログでJSON読み込みメッセージを確認
2. JSON構造が正しいか確認（Nixの構文エラーがないか）
3. サービス再起動: `systemctl restart e2m-hass-bridge`

### 配列を一部だけ変更したい

配列は完全置換されるため、元の値も含めて全て記述してください。

元の`deviceConfig.ts`を参照:
```bash
cat external-docs/e2m-hass-bridge/src/deviceConfig.ts
```

## 参考リンク

- [e2m-hass-bridge GitHub](https://github.com/nana4rider/e2m-hass-bridge)
- [ECHONET Lite検索サイト](https://echonet-lite.ka2n.dev/) - メーカーコード、デバイスクラス、プロパティ検索
- [Home Assistant Climate Integration](https://www.home-assistant.io/integrations/climate/)
- 元の設定: `external-docs/e2m-hass-bridge/src/deviceConfig.ts`
