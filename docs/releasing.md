# 发布与自动更新

首发版本为 `1.0.0`，版本来源只有 `Config/Version.xcconfig`。`CFBundleVersion` 与用户版本保持一致，由 Sparkle 比较版本并拒绝降级。安装包使用通用二进制，同时支持 Apple Silicon 和 Intel，最低 macOS 14。

## 一次性配置

### 1. 更新签名

在维护者 Mac 上执行：

```sh
bash scripts/setup-updates.sh --github
```

脚本用 Sparkle 官方工具生成 Ed25519 密钥，私钥保存在登录钥匙串的 `app.2famac` 账户中；公钥写入 `Config/Version.xcconfig`；私钥经临时文件上传至当前 GitHub 仓库的 `SPARKLE_PRIVATE_KEY` Secret 后删除临时文件。命令需要已通过 `gh auth login` 登录有仓库管理权限的 GitHub 账号。钥匙串若弹出访问请求，请允许 Sparkle 官方工具访问该项。

提交包含公钥的配置。妥善备份钥匙串中的签名密钥；发布后不要直接更换公钥，否则旧版无法验证后续更新。已有不同公钥时，脚本会拒绝覆盖。

### 2. Apple 分发凭证

在仓库 Settings → Secrets and variables → Actions 中添加下列 Secrets：

| Secret | 内容 |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | 上一步自动写入的 Sparkle 私钥，文本格式 |
| `MACOS_CERTIFICATE_P12_BASE64` | 包含私钥的 **Developer ID Application** 证书 `.p12` 的 Base64 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 的导出密码 |
| `MACOS_PROVISION_PROFILE_BASE64` | `app.2famac` 的 Developer ID 分发描述文件 Base64，需包含 `iCloud.app.2famac`、CloudKit 和 Production 环境 |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `NOTARY_KEY_BASE64` | 用于 notarization 的 App Store Connect API `.p8` 密钥的 Base64 |
| `NOTARY_KEY_ID` | 该 API 密钥的 Key ID |
| `NOTARY_ISSUER_ID` | 该 API 密钥的 Issuer ID |

对文件编码可用 `base64 -i /path/to/file | pbcopy`，然后在 GitHub Secrets 页面粘贴。不要把私钥、证书或描述文件提交到仓库。

本项目启用 App Sandbox、摄像头和 CloudKit；更新安装器使用 Sparkle 官方 Installer XPC 服务及对应的 mach lookup entitlement。正式发布必须签名并公证；凭证不完整时流水线会失败，不会降级发布不可用的安装包。Apple Developer 中还需为 App ID 启用该 iCloud 容器，并将应用所需的 CloudKit schema 部署到 Production。

## 发布 1.0.0

完成上面的配置，将本次功能、公钥与发布说明提交并推送后：

```sh
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0
```

标签触发 `.github/workflows/release.yml`：测试 → 通用架构归档和 Developer ID 导出 → 公证并 staple → 创建 ZIP 和 DMG → 用 Sparkle 签署 ZIP 并生成 appcast → 用应用内公钥独立验签 → 上传完整草稿 → 正式发布。发布附件为：

- `TwoFA-1.0.0-macos-universal.dmg`：首次安装。
- `TwoFA-1.0.0-macos-universal.zip`：Sparkle 更新包。
- `appcast.xml`：更新清单。
- `SHA256SUMS`：上述文件校验值。

应用固定读取 `https://github.com/Mean325/2FA-Auth/releases/latest/download/appcast.xml`，清单内安装包指向具体版本，避免更新清单与下载包不一致。仓库和发布附件需保持公开，客户端不携带 GitHub 访问令牌。

## 后续版本

```sh
python3 scripts/release-version.py --set 1.0.1
# 新建 docs/releases/1.0.1.md，写入中英文更新说明。
git add Config/Version.xcconfig docs/releases/1.0.1.md
git commit -m "Prepare release 1.0.1"
git push origin main
git tag -a v1.0.1 -m "Release 1.0.1"
git push origin v1.0.1
```

只接受 `v主版本.次版本.修订版本` 的稳定标签，且必须与配置一致。流水线拒绝覆盖已有版本，也拒绝把旧版本设为最新。失败且未创建 Release 时可直接重跑；若已创建但上传不全，先检查并删除该未发布草稿，再手动运行 Release macOS 工作流，填写原标签。不重打已经正式发布的版本。

用户在“通用 → 关于”中查看真实版本、手动检查更新、设置自动检查及下载；应用菜单和菜单栏右键菜单也能检查更新。默认每天检查，自动下载并验签，退出时安装；手动检查可立即安装并重新打开。Sparkle 自带下载进度、失败重试、跳过版本及安装界面。应用自有文案支持中英文，Sparkle 使用其自带本地化；切换语言后 Sparkle 弹窗会在下次启动时使用所选语言。

## 本地验证

```sh
swift test
python3 -m unittest discover -s scripts/tests
xcodebuild -project TwoFA.xcodeproj -scheme TwoFA -configuration Release \
  -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build
```

未运行密钥配置脚本的开发构建会显示“此构建尚未配置更新签名”，不启动更新器。正式发布脚本会拒绝缺少公钥的构建。

本机正式打包可在钥匙串安装 Developer ID 证书和描述文件，设置与 `scripts/release.sh` 对应的环境变量，然后运行 `bash scripts/release.sh v1.0.0`。输出位于 `dist/releases/1.0.0/`。脚本不会自动发布本机产物。

首次发布后需用正式签名的旧版验证一次完整升级：安装旧版 → 发布更高版本 → 检查更新 → 验签、安装、重启 → 确认版本变化且账号仍在。没有更新器的原开发构建需先手动安装一次 `1.0.0`。

参考：[Sparkle 集成](https://sparkle-project.org/documentation/)、[沙盒安装](https://sparkle-project.org/documentation/sandboxing/)、[更新发布](https://sparkle-project.org/documentation/publishing/)、[Apple 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
