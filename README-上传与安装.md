# LoveTrack iOS — 可编译版

这个包是 `lovetrack` 的 iOS 工程，已经改成**能直接编译**的状态，并配好了 GitHub Actions 一键出 ipa。

后端已经部署在 `https://api.jiaqiya.xyz`（香港服务器 + Cloudflare + Let's Encrypt），工程里的地址已经指向它。

---

## 我改了什么（相对原仓库）

| 文件 | 改动 | 原因 |
|---|---|---|
| `Network/BackendConfig.swift` | `http://YOUR_SERVER_IP:3000` → `https://api.jiaqiya.xyz` | 指向已部署的后端 |
| `LoveTrack.xcodeproj/project.pbxproj` | `DEVELOPMENT_TEAM = 2CG772X26Z` → `""`（3 处） | 那是原作者的签名 Team，你签不了 |
| `Secrets.xcconfig` | **新建** | pbxproj 把它当 `baseConfigurationReference` 引用，缺失直接编译失败 |
| `.github/workflows/build-ios.yml` | **新建** | 云端编译出未签名 ipa |
| `.gitignore` | **新建** | 不忽略 `Secrets.xcconfig`（pbxproj 依赖它） |

---

## 第 1 步：传到 GitHub

你没有本地 git，用网页最省事：

1. 打开 <https://github.com/new>，新建仓库
   - 名字随意，比如 `lovetrack-ios`
   - **建议选 Public**：公开仓库的 macOS runner **免费且不限分钟**
   - 选 Private 也行，免费额度约够跑 20–40 次编译
2. 进仓库页面 → 「Add file」→「Upload files」
3. 把本文件夹里的**所有内容**拖进去（含 `App/`、`Location/`、`LoveTrack.xcodeproj/` 等）
4. 点「Commit changes」

> ⚠️ **`.github` 是隐藏目录，网页拖拽可能传不上去**。
> 传完后检查仓库里有没有 `.github/workflows/build-ios.yml`。
> 没有的话，用网页手动建：仓库 → 「Add file」→「Create new file」，
> 文件名填 `.github/workflows/build-ios.yml`，把本包里该文件的内容粘进去。

---

## 第 2 步：跑编译

1. 仓库页面 → 「Actions」标签
2. 左侧选「Build iOS IPA (unsigned)」
3. 右侧「Run workflow」→ 选 `main` → 点绿色按钮
4. 等 5–10 分钟（首次会慢些，要下载依赖和 SDK）

---

## 第 3 步：下载 ipa

Actions 跑完后：

1. 点进那次运行记录
2. 拉到底部「Artifacts」
3. 下载 **`LoveTrack-unsigned-ipa`**（是个 zip，解压得到 `LoveTrack-unsigned.ipa`）

---

## 第 4 步：装到 iPhone

**这个 ipa 是未签名的，不能直接装**。三种方式：

### 方式 A：Sideloadly（推荐，免费）
1. Windows 装 [Sideloadly](https://sideloadly.io/)
2. iPhone 用数据线连电脑
3. Sideloadly 里拖入 ipa，填你的 Apple ID
4. 点 Start，按提示在 iPhone 上「信任」开发者

> 免费 Apple ID 签的 App **7 天过期**，到期重新走一遍。
> 同时最多 3 个自签 App。

### 方式 B：爱思助手
1. 装爱思助手，连手机
2. 「应用游戏」→ 导入 ipa → 它会自动用你的 Apple ID 签名安装

### 方式 C：越狱设备
直接 `filza` 或 `AltStore` 装，不受 7 天限制。

> 你工作区里已有 `说明_免越狱安装.md` 和 `2_越狱手动安装包.zip`，如果之前装 LinkUp 时用过某种方式，那套流程对这次同样适用。

---

## 当前能测什么 / 不能测什么

**能测：**
- App 启动、登录页、配对页 UI
- 主页布局（状态栏 / PartnerHero / 距离卡 / 戳一戳 / 快捷卡）
- 定位权限申请流程
- 有位置数据时显示 **MapKit 真地图**（iOS 17+，需允许定位）

**暂时不能测完整闭环：**
- **配对逻辑是占位的** —— `RelationshipStore.swift` 里有 `createPairInvite(code: "PLACEHOLDER", ...)`，
  `RealtimeSyncService` 也有一处「内存版 no-op，仅占位」。接口路径虽然和后端对得上，
  但这块业务逻辑需要补，否则走不到「配对成功」。
- 没有 App 图标（原工程缺 `Assets.xcassets`），装上会显示白色图标，不影响功能。

**后端已确认可用**（我实测过 11 项全通过）：
```
https://api.jiaqiya.xyz          REST
wss://api.jiaqiya.xyz/sync?userId=xxx   WebSocket
```
浏览器打开 `https://api.jiaqiya.xyz` 能看到后端自带的状态页。

---

## 排错

| 现象 | 原因 |
|---|---|
| Actions 报 `Build input file cannot be found: .../Secrets.xcconfig` | 那个文件没传上去，补传 |
| Actions 报 `No such file or directory: LoveTrack.xcodeproj` | 上传时多套了一层目录，确认仓库根目录能直接看到 `LoveTrack.xcodeproj` |
| Actions 报 `xcodebuild: error: The project does not contain a scheme named "LoveTrack"` | `LoveTrack.xcodeproj/xcshareddata/xcschemes/LoveTrack.xcscheme` 没传上去 |
| 编译报 `AppIcon` 相关错误 | workflow 里已带重试（跳过 AppIcon），看日志里第二次尝试是否通过 |
| App 装上但地图空白 | 见文末「地图为什么可能是假的」 |
| App 连不上后端 | 确认 `BackendConfig.swift` 里是 `https://api.jiaqiya.xyz`；也可以在 scheme 里设环境变量 `LOVETRACK_BACKEND_URL` 覆盖 |

## 地图为什么可能是假的

`RealtimeMapScreen.swift` 里地图是二选一的：

```swift
if let center = mapCenter {
    MapKitView(center: ...)   // 真·苹果地图
} else {
    MiniMap(...)              // 纯 SwiftUI Canvas 手绘的「仿高德」示意图
}
```

`mapCenter` 优先用对方位置、其次用你自己的位置，**两者都没有就显示手绘图**。
所以刚装上、还没定位、也没配对时，看到的是那张画出来的假地图，不是故障。

要看到真地图：iOS 17+、允许定位权限、并且后端有位置数据。
