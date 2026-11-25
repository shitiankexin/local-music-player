# local-music-player

**洪达快播** 独立产品仓库（含官网与 iOS 客户端）。

| 子项目 | 说明 |
|--------|------|
| [hongda-player-web](./hongda-player-web) | 官网：介绍、下载、隐私政策、用户协议 |
| [hongda-player-ios-app](./hongda-player-ios-app) | iOS 客户端（SwiftUI · iOS 18+ · FLAC + LRC） |

| 项 | 值 |
|------|------|
| 显示名 | 洪达快播 |
| Bundle ID | `chat.5min.hongdakuaibo.app` |
| 规划域名 | `https://hongdakuaibo.com` |
| GitHub | https://github.com/shitiankexin/local-music-player |

## 快速开始

### 官网

```bash
cd hongda-player-web/public
python3 -m http.server 8080
```

### iOS

```bash
cd hongda-player-ios-app
bash scripts/build-flac.sh   # 首次
xcodegen generate
open HongdaPlayer.xcodeproj
```

## 说明

原独立仓库 [`heanbian/hongda-player-web`](https://github.com/heanbian/hongda-player-web)、[`heanbian/hongda-player-ios-app`](https://github.com/heanbian/hongda-player-ios-app) 已迁入本仓库作为子目录；后续以本仓库为准。
