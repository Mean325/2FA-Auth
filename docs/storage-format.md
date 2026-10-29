# 账号保存方式

本机和 CloudKit 私有库均使用 Base64 编码的 JSON，不做应用层加密，也不读写钥匙串。

## 本机文件

位置：`~/Library/Application Support/app.2famac/accounts.base64`。沙盒构建位于对应的应用容器内。

文件是一个 Base64 字符串，解码后为 `{ "version": 1, "records": [...] }`。账号字段沿用 `VaultRecord`，其中 `secret` 是原始密钥字节的 Base64 字符串。删除记录保留墓碑，但清空 `secret`。`sortOrder` 保存拖拽后的列表顺序，账号管理和菜单栏使用同一顺序，新账号排在末尾。

文件不存在时从空账号列表开始，不检查旧数据库。写入先生成当前用户可读写的临时文件，再原子替换目标文件。只有写入成功后才更新内存和同步队列；损坏的当前格式文件不会被当作空账号覆盖。

## iCloud

CloudKit 私有区域为 `VaultZone`，记录类型为 `VaultItem` 和 `Preference`。`schemaVersion = 2` 的 `payload` 为 Base64 JSON，账号 UUID、合并规则和删除墓碑沿用当前实现。

只解析当前格式，不提供历史数据库、钥匙串或云端密文的读取与迁移功能。

从外部导入加密的 2FAS/Aegis 备份及 Google Authenticator 迁移链接仍受支持，与旧版本数据兼容无关。
