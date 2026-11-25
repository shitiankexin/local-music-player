# local-music-player

**洪达快播** 独立产品仓库（含官网与 iOS 客户端）。

| 子项目 | 说明 |
|--------|------|
| [hongdakuaibo-web](./hongdakuaibo-web) | 官网：介绍、下载、隐私政策、用户协议 |
| [hongdakuaibo-ios-app](./hongdakuaibo-ios-app) | iOS 客户端（SwiftUI · iOS 18+ · FLAC + LRC） |

| 项 | 值 |
|------|------|
| 显示名 | 洪达快播 |
| Bundle ID | `com.shitiankexin.hongdakuaibo` |
| 规划域名 | `https://hongdakuaibo.shitiankexin.com` |
| GitHub | https://github.com/shitiankexin/local-music-player |

## 快速开始

### 官网

```bash
cd hongdakuaibo-web/public
python3 -m http.server 8080
```

### iOS

```bash
cd hongdakuaibo-ios-app
bash scripts/build-flac.sh   # 首次
xcodegen generate
open hongdakuaibo.xcodeproj
```
