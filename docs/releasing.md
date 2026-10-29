# 发布与自动更新

版本来源为 `Config/Version.xcconfig`，首发 `1.0.0`。`CFBundleVersion` 与用户版本一致，安装包包含 Apple Silicon 和 Intel，最低 macOS 14。

## 默认发布：无需 Apple 证书

沿用 CodexLinxDisplay 的方式，默认使用 ad-hoc 签名，关闭 Hardened Runtime，跳过 Apple 公证，生成 DMG、ZIP 和带 Ed25519 签名的 Sparkle 更新清单。**Sparkle 更新签名始终必需，Apple Developer ID 签名和公证可选。**

当前暂时禁用 iCloud：不创建 CloudKit 容器、不启动同步任务、不记录上传队列，也不包含 iCloud entitlement。界面会显示“暂未开放，账号和设置仅保存在这台 Mac 上”。云端已有数据不会修改。恢复同步需要单独启用代码开关、重新配置 iCloud entitlement 和 Apple 分发权限。

应用与现有本机版本、CodexLinxDisplay 一样采用非沙盒分发，本地账号继续保存到 `~/Library/Application Support/app.2famac/accounts.base64`。Sparkle 使用普通应用安装器，不启用沙盒专用 Installer XPC 服务。

首次打开未公证版本时，macOS 可能显示安全拦截；请仅从本仓库 Releases 下载。发布说明会标明该版本未经 Apple 公证。

### 更新签名（已配置）

维护者首次配置或恢复新电脑时执行：

```sh
bash scripts/setup-updates.sh --github
```

公钥写入 `Config/Version.xcconfig`，私钥保存在登录钥匙串的 `app.2famac` 账户中，并写入 GitHub 仓库的 `SPARKLE_PRIVATE_KEY` Secret。私钥不进入代码、日志或安装包。备份钥匙串中的签名密钥；已发布后不要直接更换公钥。

默认模式只需要这一个 Secret。仓库变量 `ENABLE_SIGNED_RELEASES` 不设置或为 `false` 即可。

### 发布版本

提交代码、版本配置及 `docs/releases/1.0.0.md` 后推送标签：

```sh
git push origin main
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0
```

流水线依次执行测试、通用构建、ad-hoc 签名验证、ZIP/DMG 打包、生成 Sparkle 清单、用应用内公钥独立验签，上传所有附件到草稿后再发布：

- `TwoFA-1.0.0-macos-universal.dmg`：首次安装。
- `TwoFA-1.0.0-macos-universal.zip`：Sparkle 更新包。
- `appcast.xml`：更新清单。
- `SHA256SUMS`：附件校验值。

应用读取 `https://github.com/Mean325/2FA-Auth/releases/latest/download/appcast.xml`。清单中的 ZIP 指向具体版本，仓库与发布附件需保持公开，客户端不使用 GitHub Token。

后续版本：

```sh
python3 scripts/release-version.py --set 1.0.1
# 创建 docs/releases/1.0.1.md，填写中英文更新说明，然后提交并推送。
git tag -a v1.0.1 -m "Release 1.0.1"
git push origin v1.0.1
```

标签必须与配置版本一致。流水线拒绝覆盖已有 Release、拒绝将旧版本设为最新。若失败时已创建未发布草稿，检查并删除该草稿后，再在 Release macOS 工作流中填写原标签重跑；已正式发布的版本不能重打。

用户可在“通用 → 关于”、应用菜单及菜单栏右键菜单中检查更新。默认每天自动检查并下载，签名验证通过后于退出时安装；手动检查可以立即安装并重新打开。自动检查和下载开关可分别设置。应用支持中英文；Sparkle 使用其自带本地化，修改语言后其弹窗在下次启动时生效。

## 可选：Apple 签名与公证

将仓库变量 `ENABLE_SIGNED_RELEASES` 设为 `true`，并添加以下 Actions Secrets：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | 含私钥的 Developer ID Application `.p12` 文件 Base64 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `NOTARY_KEY_BASE64` | 公证用 App Store Connect API `.p8` 密钥 Base64 |
| `NOTARY_KEY_ID` | API Key ID |
| `NOTARY_ISSUER_ID` | API Issuer ID |

此模式使用 Developer ID 归档与导出，开启 Hardened Runtime，对应用和 DMG 公证并 staple 后再签署 Sparkle 更新 ZIP。开启后缺少 Apple 凭证会明确失败，不自动切回 ad-hoc。当前禁用了 iCloud，因此不要求 iCloud 分发描述文件；Apple 签名也不会自动开启 iCloud。

## 本地验证与打包

```sh
swift test
python3 -m unittest discover -s scripts/tests
```

本地默认打包：

```sh
# 将钥匙串私钥导出到受保护的临时目录，不打印私钥。
umask 077
key_dir="$(mktemp -d -t twofa-release)"
trap 'rm -f "$key_dir/signing.private"; rmdir "$key_dir"' EXIT
.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account app.2famac -x "$key_dir/signing.private"
SPARKLE_PRIVATE_KEY_FILE="$key_dir/signing.private" bash scripts/release.sh v1.0.0
```

输出位于 `dist/releases/1.0.0/`，本地脚本不会自动上传。已存在的输出目录会拒绝覆盖，请先移到别处再重建。正式的旧版本升级测试需在发布更高版本后完成；原来没有更新器的开发构建需要先手动安装一次 `1.0.0`。

参考：[Sparkle 集成](https://sparkle-project.org/documentation/)、[更新发布](https://sparkle-project.org/documentation/publishing/)、[Apple 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
