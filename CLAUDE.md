# Project Context

## Environment

- **Current Machine**: Development/editing machine (NixOS)
- **Target System**: `sensors` host (別マシン)
- **Important**: このマシンは対象システム（sensors）ではありません

## Workflow

### What You Can Do on This Machine
- ✅ NixOS configuration の編集
- ✅ Syntax チェック: `nix flake check`
- ✅ Build テスト: `nix build .#nixosConfigurations.sensors.config.system.build.toplevel`
- ✅ Dry build: `nixos-rebuild dry-build --flake .#sensors`

### What Requires the Target System
- ❌ `sudo nixos-rebuild switch --flake .#sensors` - 対象システム（sensors）で実行する必要があります
- ❌ サービスのログ確認（journalctl）
- ❌ 実機での動作確認

## Deployment Process

1. このマシンで設定を編集
2. 必要に応じてビルドチェック
3. Git commit & push
4. **対象システム（sensors）で** `sudo nixos-rebuild switch --flake .#sensors` を実行

## Notes

- e2m-hass-bridge の設定変更などは、sensors マシンでのデプロイが必要
- ローカルでのシンタックスチェックやビルドテストは有用
