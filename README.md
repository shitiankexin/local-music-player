# LocalFLAC Player — 本地 FLAC + LRC 播放器（增强版文件管理）

> **项目状态：用于 Xcode 构建与调试的完整源码工程，非已签名 IPA；本环境尚未完成 Xcode 实际编译。**
> 这是在上一版 `LocalFLACPlayer_Source` 基础上迭代的完整项目，并非仅供展示的 UI 设计。
> 当前执行环境为 Linux，已经做 Swift 语法检查、Foundation 逻辑类型检查和便携文件系统集成测试；无法在此执行 macOS Xcode iOS SDK 编译、Apple 签名或 iPhone 真机音频测试。

## 1. 主要功能

已有的播放器部分 **保持不变**：

- **无损播放**：Xiph.org libFLAC 1.5.0 + `AVAudioEngine`，支持单声道/立体声 `.flac`（16/24-bit，面向 44.1/48/96/192 kHz 源文件测试）；分块读取、Float32 PCM、音质优先模式。
- **音乐资料库**：歌曲、专辑、歌手、播放列表、标签、内嵌封面。
- **LRC 歌词**：UTF-8 / UTF-16 文本、行级同步、高亮、滚动、手动时间偏移。
- **系统播放**：锁屏/控制中心、后台播放、耳机切歌、进度跳转。

**本次新增**：

| 功能 | 具体行为 |
| --- | --- |
| 文件夹导入 | 选择单个或多个文件夹，递归导入 `.flac` / `.lrc`；保留子文件夹层级 |
| 增量扫描 | 依照相对路径 + 文件大小 + 修改时间缓存元数据；未变化的 FLAC 不重复解码；处理新增/删除/更新，清理封面孤儿缓存 |
| 内容去重 | 导入新 FLAC 时先流式计算 SHA-256，仅与相同大小的现有文件校验，完全相同内容跳过 |
| 检测已有重复 | “管理”页按文件大小筛选候选，对候选计算 SHA-256，逐组显示重复副本与可回收空间，**不自动删除** |
| 同名不同内容 | 保留为 `歌曲 (2).flac`，成对 `.lrc` 自动映射成 `歌曲 (2).lrc` |
| 批量歌词匹配 | 优先同目录同名；其他目录 LRC 按唯一文件名或唯一歌曲标题匹配，复制为音频同目录 `.lrc`；歧义保留待人工处理 |
| 删除歌曲 | 歌曲列表左滑删除，或在重复组指定某一份删除；同时删除该 FLAC 同目录的同名 LRC，并从播放列表移除对应引用 |
| 导入进度 | 显示当前文件、文件个数与总字节进度；长文件按 1 MiB 分块复制、可请求取消；失败记录原因 |
| 空间统计 | FLAC、LRC、提取封面分别统计，显示音乐相关占用、已配对歌词首数和设备可用空间 |

## 2. 从 Mac 构建（MacBook Pro M1/M2/M3/M4）

要求：Xcode（对应系统允许的稳定版）、macOS、Homebrew、iPhone iOS 17 或更新。

```bash
brew install cmake ninja xcodegen git
cd LocalFLACPlayer
bash scripts/build-flac.sh
xcodegen generate
open LocalFLACPlayer.xcodeproj
```

在 Xcode 中：
1. 选择 Target `LocalFLACPlayer` → `Signing & Capabilities` → 你的 Apple Team。
2. 修改 `com.example.localflacplayer` 为自己的唯一 Bundle Identifier。
3. 在 iPhone 真机运行；第一首测试建议使用小文件 16-bit/44.1 kHz FLAC 与 UTF-8 LRC。
4. 若要运行 iOS XCTest，选择 `LocalFLACPlayerTests` Scheme（如果没有创建测试 Scheme，直接执行 Product → Test）。

> `Vendor/libFLAC.xcframework` 不附带在压缩包中，由 `scripts/build-flac.sh` 从 Xiph.org 官方 FLAC 1.5.0 源码编译。当前脚本面向 arm64 iPhone 与 arm64 模拟器。Xcode 工程需要 `xcodegen generate` 生成；**不能直接用 Windows 生成 iPhone IPA**。

## 3. 如何使用 

### A. 整文件夹导入

1. 在 Mac 上将 FLAC/LRC 整理到一个父文件夹；可隔空投送到 iPhone「文件」，或放入 iCloud Drive。
2. 打开 LocalFLAC → 底部 **管理** → **导入整个文件夹**。
3. 在系统文件选择器选中文件夹。仅 `.flac` / `.lrc` 会进入曲库，其余不复制。
4. 在“任务进度”查看完成百分比，可点击“取消当前任务”。
5. 完成后程序自动重新扫描曲库。

例如选择：

```text
Mac/流行音乐/
  周杰伦/七里香/晴天.flac
  周杰伦/七里香/晴天.lrc
  林俊杰/江南.flac
  林俊杰/江南.lrc
```

最终文件保存在 App 的 `Documents/Music/流行音乐/...`，完整保留歌手与专辑层级。

### B. 单独 FLAC / LRC 导入

从 **歌曲** 页右上角导入，或 **管理 → 导入 FLAC / LRC 文件**，支持多选。如果选择同一目录下同名歌曲+歌词，会将两者关联到同一个实际文件名。独立歌词进入 `Documents/Music/`，可之后使用“批量匹配”将其复制到正确歌曲目录。

### C. Finder 数据线文件共享

通过 Mac Finder → iPhone → **文件** → LocalFLAC，直接向 App Documents 复制文件/文件夹。应用重新进入前台时触发增量扫描。音频文件**原字节复制**，不经过 Apple Music 同步或转换，也不会自动压缩。

### D. AirDrop

若系统显示“打开方式”可直接转交 LocalFLAC；否则存入 iPhone“文件”App，再用 LocalFLAC 内部导入。经 iOS “打开方式”放入 App `Documents/Inbox` 的文件，成功导入后会删除 Inbox 中的中间副本，避免占用双份空间。

## 4. LRC 匹配规则

1. 歌曲同目录同名 `.lrc` 优先（例如 `晴天.flac` + `晴天.lrc`）。
2. 点击 **管理 → 批量匹配 LRC**，对分散的 LRC 仅选择**唯一**的文件名匹配；其次尝试 FLAC 标签中的唯一歌曲标题。
3. 相同文件名或歌曲标题对应多首歌时**不自动覆盖或猜测**，显示“多重候选”与示例名称。
4. 已配对的 LRC 不覆盖；把跨目录歌词复制到歌曲旁边后，原始歌词仍保留，不会自动删除。
5. 歌词建议存为 UTF-8；GBK/Big5 尚未支持，需要自行转换编码。

## 5. 重复检测的准确含义

- 使用 **文件内容的 SHA-256**，而不是歌名相似度、音频指纹或压缩后的波形。
- 同一首歌不同压制、不同编码参数、改过标签/封面，即使听起来相同，SHA-256 也会不同；**不会自动合并**。
- 只给出估算“最多可回收字节”，用户需要在重复组中决定删除哪一份。
- 发现 Finder 直接拷入的重复文件，先执行增量扫描，再执行“按 SHA-256 检测重复歌曲”。
- 为节省大量音乐的扫描时间，只有**字节数相同**的候选才计算哈希；已计算哈希会缓存在曲库中，失效条件是大小/修改时间变化。

## 6. 删除与取消行为

- 删除会 **直接永久删除 App 沙盒中的 FLAC** 和其**同目录同名 LRC**，不是移到回收站。首次使用前请保留 Mac 上的原始备份。
- 删除时播放器会停止当前正在被删除的歌曲，之后刷新曲库，并从播放列表删除该 UUID 引用。其他歌曲、其他 LRC 不被自动删除。
- 如果取消批量导入，已经完整复制并提交的文件会保留；当前正在写入的暂存文件会清理。重新导入时，重复歌曲会被哈希校验跳过。取消不具备“撤销本次全部文件”的事务语义。
- 文件提供商（例如 iCloud Drive）可能需要下载文件或协调读取；在这些系统等待阶段，取消不一定立即响应。

## 7. 升级兼容

可以直接升级 V1 工程；无需改动 `Documents/Music` 的已有音乐：

- 旧版 `catalog.json` 中没有 `modifiedAt`、`sha256` 两个字段，均为可选字段，因此可以兼容解码。
- 首次运行 会对旧曲库做一次必要的重新读取，补足修改时间；此后文件未变化时会重用缓存。
- 文件相对路径不变时歌曲 UUID 继续保留，原播放列表保持有效；**在 Finder 中移动或重命名歌曲后，其路径将被视为一条新记录，原播放列表引用可能移除**。
- 自己签名安装时保持原 Bundle Identifier；如果更换 ID 或删除 App，原沙盒数据可能无法直接保留。任何升级前建议备份 Documents。

## 8. 文件清单

```text
LocalFLACPlayer/
├── project.yml
├── scripts/build-flac.sh
├── Vendor/README.md
├── FLACPlayer/
│   ├── App/LocalFLACPlayerApp.swift
│   ├── Audio/FLACBridge.c / .h, FLACDecoder.swift, FLACAudioEngine.swift
│   ├── Models/
│   │   ├── MusicTrack.swift                 # 兼容版增量索引字段
│   │   └── LibraryManagementModels.swift   # 进度、空间、统计报告
│   ├── Services/
│   │   ├── MusicLibrary.swift              # 主线程调度 + 后台任务编排
│   │   ├── LibraryIndexer.swift            # 增量扫描 / 统计
│   │   ├── LibraryImportWorker.swift       # 文件夹 / 流式复制 / 内容去重
│   │   ├── LibraryMaintenanceWorker.swift  # LRC 匹配 / 重复检测 / 删除
│   │   ├── LibraryFileRules.swift          # 规范化匹配 / 路径工具
│   │   ├── FileDigest.swift                # CryptoKit SHA-256 文件流式哈希
│   │   ├── LRCParser.swift
│   │   └── PlayerStore.swift
│   ├── Views/
│   │   ├── LibraryManagerView.swift        # 新增管理页
│   │   └── RootView.swift, SongListView.swift, ...
│   └── Support/
│       ├── Info.plist                      # Finder 共享 / 后台音频
│       ├── PrivacyInfo.xcprivacy           # 文件时间戳 / 空间 API 使用原因
│       └── BridgingHeader.h
├── Tests/LRCParserTests.swift
├── Tests/LibraryManagementTests.swift
├── TestsPortable/                          # Linux 可重复的文件集成测试（使用替身哈希）
└── CHANGELOG.md
```

## 9. 测试与待验证项

**本地已完成（不依赖 iOS SDK）：**
- 全部 Swift 文件语法解析。
- Foundation-only 模块类型检查。
- `LibraryIndexer` 在替身 FLAC 元数据解码器下的真实目录扫描测试：首次新增、再次缓存复用、同大小但新 mtime 更新、同名歌词匹配、文件删除。
- 运行 `bash TestsPortable/run-linux.sh` 可复现便携集成测试（需 Linux Swift 工具链）。
- `LibraryImportWorker` 的实际文件读写行为测试：文件夹层级、重导入跳过、同名冲突重命名与伴随歌词、独立 LRC 匹配、内容重复分组、指定文件删除。（Linux 便携测试使用替身哈希实现模拟 CryptoKit 接口，正式 iOS 源码使用 CryptoKit SHA-256。）
- `Info.plist`、`PrivacyInfo.xcprivacy` 的结构检查。

**必须到 Mac Xcode / iPhone 上验证：**
- 构建 `libFLAC.xcframework`、XcodeGen 生成工程、Xcode 实际编译及 XCTest 运行。
- 16/24-bit、44.1/48/96/192kHz FLAC 长时间播放与资源占用。
- iCloud/第三方“文件”提供商的文件夹选取、下载与授权；单次导入 10GB/50GB 的取消与恢复。
- Finder 大量文件导入、锁屏、后台切歌、蓝牙与 USB DAC 切换。
- 无磁盘空间时导入中断、文件在扫描时被 Finder 修改、20,000+ 歌曲的性能。

## 10. 技术说明

- **离线**：音频、歌词、曲库索引完全在 App 本地。没有线上服务和上传功能。
- **文件安全**：使用安全作用域授权访问外部文件，`NSFileCoordinator` 配合文件提供商，按块读写；忽略符号链接，保留冲突文件而非覆盖。
- **后台操作**：长时间复制、FLAC 标签扫描和哈希计算在独立任务进行，UI 接收进度通知。
- **隐私清单**：本地内容修改时间、文件大小与设备可用空间的访问理由见 `PrivacyInfo.xcprivacy`。如果日后增加其他 API，仍需重新检查 App Store 的隐私申报。
- **音质**：复制文件内容不改变字节数据；播放器保持 FLAC 无损解码、无默认 EQ/额外音效。最终是否 bit-perfect 取决于 iOS 输出链路、设备和 DAC，不作保证。
- **许可**：libFLAC 由 Xiph.org 维护并遵循其 BSD 风格许可。发行 App 前请保留所需许可证和版权声明。

参考：[Apple fileImporter](https://developer.apple.com/documentation/swiftui/view/fileimporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:onCancellation:)) · [Apple FileManager](https://developer.apple.com/documentation/foundation/filemanager) · [Apple 隐私清单理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons) · [libFLAC](https://xiph.org/flac/api/)
