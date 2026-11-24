# 洪达快播 — 图标与上架素材

由 `scripts/generate_icons.py` 生成。重新导出：

```bash
python3 scripts/generate_icons.py
```

## 工程内

| 文件 | 用途 |
|------|------|
| `HongdaPlayer/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | 默认外观 1024×1024（无透明） |
| `AppIcon-Dark.png` | iOS 18 深色外观 |
| `AppIcon-Tinted.png` | iOS 18 着色外观（模板） |
| `Logo.imageset/logo.png` | 应用内字标 |

单尺寸 1024 App Icon 即可；Xcode 会派生主屏 / 设置 / 通知等尺寸。

## store/artwork（上架与外发）

| 文件 | 尺寸 | 用途 |
|------|------|------|
| `ic_launcher_1024.png` | 1024×1024 | App Store Connect 营销图标 |
| `ic_launcher_512.png` | 512×512 | 预览 / 文档 |
| `ic_launcher_foreground_1080.png` | 1080×1080 | 透明前景层（跨端复用） |
| `logo.png` | 1024×320 | 横版字标 |
| `logo_mark.png` | 512×512 | 透明圆形标 |
| `ios/` | 常用派生预览 | 真机对照用，非必须上传 |

`screenshots/`、`creative/` 为本地生成目录（已 gitignore）。
