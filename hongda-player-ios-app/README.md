# hongda-player-ios-app

**洪达快播** — iOS 本地 FLAC + LRC 音乐播放器。独立产品；运营方：诗天可信。

> **位置**：本工程位于仓库 [`shitiankexin/local-music-player`](https://github.com/shitiankexin/local-music-player) 的 `hongda-player-ios-app/` 子目录。官网见同仓库 `hongda-player-web/`。

| 项 | 值 |
|------|------|
| Bundle ID | `com.shitiankexin.hongdakuaibo` |
| 显示名 | 洪达快播 |
| 版本 | `1.0.0`（Build `1`）— 见 `HongdaPlayer/Info.plist` 与 `MARKETING_VERSION` |
| 技术 | SwiftUI · Observation · AVAudioEngine · libFLAC · MediaPlayer · CryptoKit |
| 最低系统 | **iOS 18** |
| 设备 | iPhone / iPad |
| 工程 | `HongdaPlayer.xcodeproj`（`project.yml` + XcodeGen） |
| 许可 | [LICENSE](./LICENSE)（Apache-2.0）；libFLAC 另见 Xiph BSD 风格许可 |

## 功能

- 四栏：歌曲 / 资料库 / 列表 / 管理
- 无损播放：libFLAC + `AVAudioEngine`（16/24-bit，常见采样率）
- 曲库：专辑、歌手、播放列表、排序、封面
- LRC：行级同步、偏移、锁屏 / 控制中心 / 后台音频
- 文件管理：文件夹导入、增量扫描、SHA-256 去重、批量歌词匹配、空间统计
- 音效：可选 10 段 EQ + 混响（默认原音旁路）

数据仅存本机：`Documents/Music` + `Application Support/HongdaPlayer`。

---

## 架构（iOS 18+）

```text
HongdaPlayer/
├── HongdaPlayerApp.swift      # @State AppModel → environment
├── Data/
│   ├── AppModel.swift         # 拥有 MusicLibrary + PlayerStore
│   └── AppPreferences.swift   # 类型化 UserDefaults / AppStorage 键
├── Features/
│   ├── Root/                  # Tab API + mini player
│   ├── Library/               # 歌曲 · 资料库 · 列表 · 管理
│   └── Player/                # 全屏播放 · 封面 · 歌词
├── Services/                  # @Observable 曲库 / 播放 / 导入 / 索引
├── Models/
├── Audio/                     # FLAC bridge · AVAudioEngine
└── Assets.xcassets/           # AppIcon（含 Dark / Tinted）· Logo · AccentColor
```

要点：

- `MusicLibrary` / `PlayerStore` 使用 **`@Observable`**，经 `.environment` 注入
- 列表行单独观察播放状态，避免整表随进度刷新
- Root 使用 iOS 18 **`Tab`**；iOS 26.1+ 使用 `tabViewBottomAccessory`

---

## 开发

| 工具 | 用途 |
|------|------|
| Xcode 16+（iOS 18 SDK） | 编译 / 真机 / Archive |
| Homebrew：`cmake` `ninja` `xcodegen` | 编 libFLAC、生成工程 |
| Python3 + Pillow | `scripts/generate_icons.py` |

```bash
# 若 xcode-select 仍指向 Command Line Tools：
# sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# 或：export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

brew install cmake ninja xcodegen
bash scripts/build-flac.sh
xcodegen generate
open HongdaPlayer.xcodeproj
```

Signing → 选择 Team → `⌘R`。

### 图标

```bash
python3 scripts/generate_icons.py
```

详见 `store/artwork/README.md`。

---

## 签名与发布

```bash
cp ExportOptions.plist.example ExportOptions.plist   # 填 teamID
./scripts/release.sh                                 # → store/release/hongda-kuaibo-1.0.0.ipa
```

版本两处保持一致：`HongdaPlayer/Info.plist` 与 Target `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。

---

## 使用摘要

1. **管理 → 导入整个文件夹**：递归导入 `.flac` / `.lrc`，保留目录层级
2. Finder 文件共享：Mac → iPhone → 文件 → 洪达快播
3. 歌词：同目录同名优先；**批量匹配 LRC** 仅唯一候选时自动配对
4. 重复检测：同大小再算 SHA-256，不自动删除

---

## Git

**提交**：源码、`project.yml`、`HongdaPlayer.xcodeproj`、Assets、`scripts/`、签名示例、`LICENSE`、文档

**勿提交**：`ExportOptions.plist`、`signing.properties`、`signing/material/`、`build/`、`.build/`、`store/release/`、`xcuserdata/`（见 `.gitignore`）

---

## 说明

离线本地播放器；发行前请保留 Apache-2.0 与 libFLAC 所需声明。
