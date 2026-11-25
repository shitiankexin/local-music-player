# CHANGELOG

## 1.0.0 — 洪达快播

### Added
- 产品定名 **洪达快播**（`com.shitiankexin.hongdakuaibo`），版本自 `1.0.0` / Build `1` 起计。
- iOS 18 工程脚手架：`.gitignore`、签名示例、`scripts/release.sh`、`store/`、`signing/`、Apache-2.0。
- 品牌图标流水线：`scripts/generate_icons.py`（含 Dark / Tinted、商店尺寸）。
- Feature 分区：`Features/Root|Library|Player`，`Data/AppModel` + `AppPreferences`。

### Modernized
- `MusicLibrary` / `PlayerStore` → **`@Observable`**，经 `environment` 注入；Root 使用 iOS 18 **`Tab`**。
- 偏好键集中到 `AppPreferences`；远程控制回调改用 `Task { @MainActor in … }`。
- Swift `5.10`、并发检查 `targeted`；古典 EQ 预设补全；删除文案适配 iPhone/iPad。
- LRC 解析去掉脆弱强制解包；管理页展示品牌 Logo。

### Included
- libFLAC + `AVAudioEngine` 无损播放、LRC、Now Playing / 后台音频。
- 文件夹导入、增量扫描、SHA-256 去重、批量 LRC 匹配、排序与可选 EQ。

### Known limitations
- 需本机 `build-flac.sh` + `xcodegen generate` 后用 Xcode 验收。
- 标签不同的同曲 FLAC 不视为重复；LRC 仅唯一文件名/标题自动匹配。
- App 外重命名/移动歌曲可能使播放列表引用失效。
