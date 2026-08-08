# 发布流程

GitHub Release 工作流需要以下 Repository Secrets：

| Secret | 用途 |
| --- | --- |
| `DEVELOPER_ID_APPLICATION` | Developer ID Application 证书全名 |
| `DEVELOPER_ID_P12_BASE64` | Base64 编码的 `.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | `.p12` 密码 |
| `NOTARY_KEY_BASE64` | Base64 编码的 App Store Connect API `.p8` |
| `NOTARY_KEY_ID` | App Store Connect API Key ID |
| `NOTARY_ISSUER_ID` | App Store Connect Issuer ID |

凭据不得写入仓库。

## 发布新版本

1. 更新 `CHANGELOG.md` 和版本号。
2. 确认 `swift test` 和 `Scripts/build-app.sh` 通过。
3. 创建并推送标签：

```bash
git tag v0.1.0
git push origin v0.1.0
```

4. GitHub Actions 构建通用 App，导入 Developer ID，生成 DMG，提交 Apple 公证并上传 Release。
