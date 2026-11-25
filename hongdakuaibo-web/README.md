# hongdakuaibo-web

**洪达快播** 官网：产品介绍、下载入口、隐私政策与用户协议。

| 项 | 值 |
|------|------|
| 站点 | `public/` 静态站点（可直传任意静态托管） |
| 品牌域名（规划） | `https://hongdakuaibo.com` |
| 运营方 | 诗天可信 |
| 关联 iOS | [hongdakuaibo-ios-app](https://github.com/shitiankexin/local-music-player/tree/main/hongdakuaibo-ios-app) |
| 许可 | [LICENSE](./LICENSE)（Apache-2.0） |

## 页面

| 路径 | 说明 |
|------|------|
| `/` | 首页介绍 |
| `/download.html` | 下载 |
| `/about.html` | 关于 |
| `/privacy.html` | 隐私政策 |
| `/terms.html` | 用户协议 |

元数据见 `public/site.json`。

## 本地预览

```bash
cd public
python3 -m http.server 8080
# 打开 http://127.0.0.1:8080/
```

## 目录

```text
hongdakuaibo-web/
├── public/
│   ├── index.html
│   ├── download.html
│   ├── about.html
│   ├── privacy.html
│   ├── terms.html
│   ├── css/site.css
│   ├── img/
│   ├── site.json
│   ├── robots.txt
│   ├── sitemap.xml
│   └── site.webmanifest
├── LICENSE
└── README.md
```

上架 App Store 后，请更新 `download.html` 与 `site.json` 中的 `appStoreUrl`。
