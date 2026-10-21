# iOS 安装包（全能签等自签工具）

这里是 Folia 的 iOS 外壳 App。它是一个原生的 WKWebView 应用，打开后加载**你部署好的 Folia 网页版**。在线搜索、播放、歌词、扫码登录和导入歌单，用的都是网页版那套接口，和在浏览器里打开 Folia 完全一样。

GitHub Actions 编出的是**未签名的 IPA**，要用全能签（或爱思助手、Sideloadly、TrollStore 等）签名后才能安装。

## 一、先把服务端部署好

App 里不带音乐接口，网易云、QQ 音乐、酷狗的请求都由服务端转发。所以先要有一个能从手机访问的 Folia 网页版：

| 部署方式 | 适合 | 说明 |
| --- | --- | --- |
| **Docker 全栈（推荐）** | 有 VPS 或 NAS | 网页、网易云、QQ 音乐、酷狗接口一次全部起好，扫码登录和导入歌单最稳。步骤见 [`deploy/docker/README.md`](../../deploy/docker/README.md) |
| Vercel / Cloudflare | 没有服务器 | 一键部署网页版，但网易云接口要另外部署一个实例，再把地址填进 `VITE_NETEASE_API_BASE`。见项目 README 的“一键部署” |

部署完先在手机 Safari 里打开这个地址，确认能登录、能看到歌单，再装 App。

几点建议：

- **用 HTTPS 域名**，比如 `https://folia.example.com`（NAS 的反向代理加证书即可）。只在家里用的话，`http://NAS-IP:18080` 这种局域网地址也能连，但出门就连不上了。
- Docker 部署的 `FOLIA_FORWARD_CLIENT_IP` 保持默认的 `false`；QQ 音乐想重启容器后不掉登录，配上 `QQ_AUTH_SESSION_PATH` 和 `QQ_SESSION_SECRET`。

## 二、拿到 IPA

每次 `packaging/ios/` 有改动并推到 GitHub，`iOS IPA` 工作流（`.github/workflows/ios-ipa.yml`）都会在 macOS 机器上编一次，把结果发到仓库的 `ios-latest` 预发布。下载地址是固定的：

```text
https://github.com/<你的用户名>/folia-major/releases/download/ios-latest/Folia-unsigned.ipa
```

也可以在仓库的 Actions 页面手动运行 `iOS IPA`。运行时的 `server_url` 填你的服务端地址，App 第一次打开就会直接连它，不用再手动输入。想让每次自动出包都带上这个地址，在仓库 Settings → Secrets and variables → Actions → Variables 里加一个 `FOLIA_IOS_SERVER_URL`。

网页功能的更新只看服务端：服务端更新后 App 里马上就是新版，**不需要重新出包、重新签名**。只有改了 `packaging/ios/` 里的外壳代码才需要重新出包。

## 三、用全能签安装

1. 在全能签里导入 IPA：可以填上面的下载地址直接下载，也可以先在 Safari 里下载好，再用“共享 → 全能签”导入。
2. 选择你的证书签名。Bundle ID 默认是 `com.folia.major`，需要的话可以在签名设置里改。
3. 签完后安装，回到桌面打开 Folia。
4. 证书过期或被撤销时，App 就打不开了，用全能签重新签一次再安装。设置、登录状态会保留（只要 Bundle ID 不变）。

## 四、App 的用法

- **第一次打开**：填服务端地址（构建时预置了地址的话会直接连接）。不写 `http://` 时默认按 `https://` 连接。
- **摇一摇手机**：弹出菜单，可以刷新页面或更换服务端。连不上服务端时，页面上也有“重试”和“更换服务端”。
- **后台播放**：锁屏、切到别的 App 时会继续播放，锁屏界面和控制中心一般也能切歌、暂停（用的是网页的 Media Session）。
- **扫码登录**：二维码就显示在这台手机上，没法用同一台手机去扫。可以截图，再在网易云 / QQ 音乐 / 酷狗 App 的“扫一扫”里从相册选这张截图；或者用另一台设备显示二维码。登录一次后，导入歌单、收藏都和网页版一样。
- **导出文件**（歌单 m3u8、歌词、同步备份等）：下载完会弹出分享面板，可以存到“文件”或发给别的 App。
- **外部链接**：会用 Safari 打开，不会把 App 里的页面换掉。

## 用不了的功能

以下功能是网页版在 iOS 上本来就没有的，或者只有桌面版才有：

- 桌面壁纸、窗口置顶、遥控窗、Now Playing 接入、视频导出等 Electron 桌面版独有的功能。
- 选择本地音乐文件夹（iOS 不支持 File System Access API）。
- 离线打开（App 每次都从服务端加载页面，服务端连不上时只显示重试页）。

## 自己在 Mac 上编

需要 Xcode 15 以上和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
FOLIA_SERVER_URL=https://folia.example.com packaging/ios/build-ipa.sh
# 产物在 release/ios/Folia-<版本>-unsigned.ipa
```

想直接在 Xcode 里调试：在 `packaging/ios` 里运行 `xcodegen generate`，打开 `Folia.xcodeproj`，选上自己的开发者账号就能装到手机上。连着 Mac 时可以用 Safari 的“开发”菜单检查 App 里的网页。

文件说明：

- `project.yml`：XcodeGen 工程描述；`Folia.xcodeproj` 由它生成，不入库。
- `Folia/Info.plist`：权限说明、后台音频、ATS（允许连 http 地址），以及构建时预置的服务端地址 `FoliaDefaultServerURL`。
- `Folia/WebViewController.swift`：加载页面、站内站外链接、弹窗、新窗口、下载、摇一摇菜单。
- `Folia/ServerSettings.swift`：服务端地址的保存和整理。
- `AppIcon.svg`：App 图标的源文件（由 `public/icon.svg` 改成铺满的方形），`Folia/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` 是用它渲染的。
