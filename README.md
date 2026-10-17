# LoveTrack iOS（AI 修改版）

情侣实时定位 App 的 **iOS 客户端**。基于开源项目改造而来，后端另有独立实现。

> **本仓库是 [`2000lla/lovetrack`](https://github.com/2000lla/lovetrack) 的修改版，修改工作全部由 AI 助手完成。**
> 原始作品与作者：**2000lla**。本仓库不声称对原始代码拥有版权。

---

## ⚠️ 请先读这两段

### 一、来源与授权状况

| 项 | 说明 |
|---|---|
| 原始项目 | [`2000lla/lovetrack`](https://github.com/2000lla/lovetrack) |
| 原始许可证 | **无 LICENSE 文件**，未声明任何开源协议 |
| 依默认版权规则 | 视为「保留所有权利（All Rights Reserved）」 |
| 本仓库定位 | **个人学习 / 自用改造**，不做商业分发、不售卖 |
| 如原作者有异议 | 请开 Issue 或联系，会立即下架删除 |

**请勿把本仓库当作开源项目二次分发。** 想用请回到原仓库，并自行向原作者确认授权。

### 二、这是 AI 修改的代码

本仓库相对原始项目的**全部改动**由 AI 助手在用户明确需求下完成，包括：

- 构建配置修复（让工程能真正编译出 ipa）
- 配对流程的边界情况加固
- GitHub Actions 工作流
- 全部文档（本文、CHANGELOG、安装说明）
- 发布/构建/校验用的辅助脚本

**人类作者负责的部分**：原始 SwiftUI 界面、地图、定位、关系模型等全部业务代码（即 `App/`、`Map/`、`Location/`、`UI/`、`Models/`、`Network/`、`Relationship/`、`Log/` 下的原始实现）。

**AI 修改的可靠性边界，请务必了解：**

- ✅ 每次改动都经过 **GitHub Actions 真实编译**（macOS + Xcode），编译通过才会发布
- ✅ 产出的 ipa 结构、架构（arm64）、Info.plist 关键字段都做过自动校验
- ❌ **没有经过完整的人工代码审查**
- ❌ **没有经过双真机的端到端流程验证**（配对→互相看位置），这部分需要你自己实测

---

## 功能

- **配对**：A 生成 6 位邀请码 → B 输入 → 双方绑定
- **实时位置**：WebSocket 双向推送，对方位置在地图上实时移动
- **距离**：主页显示与 TA 的实时距离
- **后台定位**：`UIBackgroundModes: location` + 后台保活
- **戳一戳**：6 种互动（戳/抱抱/亲亲/想你/加油/晚安）
- **守护模式**：标准 / 实时两档，可暂停共享
- **离线兜底**：WS 断开时用 HTTP 轮询拉对方最后位置

---

## 相对原仓库的改动

### A. 构建修复（不修就编不过）

| # | 文件 | 问题 | 处理 |
|---|---|---|---|
| 1 | `LoveTrack.xcodeproj/project.pbxproj` | `DEVELOPMENT_TEAM = 2CG772X26Z`（原作者签名 Team，别人无法签名） | 清空（3 处），改用无签名编译 |
| 2 | `Secrets.xcconfig` | **文件不存在**，但 `pbxproj` 把它作为 `baseConfigurationReference` 引用 → 编译直接失败 | 新建空模板，并在 `.gitignore` 里显式保留 |
| 3 | `Network/BackendConfig.swift` | 后端地址是占位符 `http://YOUR_SERVER_IP:3000` | 改为已部署的 `https://api.jiaqiya.xyz` |
| 4 | `.github/workflows/build-ios.yml` | 没有 CI，云端编不出 ipa | 新建工作流（无签名 Release 构建 + 产物上传） |

### B. 配对流程加固（原实现的真实缺陷）

| # | 位置 | 问题 | 修复 |
|---|---|---|---|
| 5 | `App/PairScreen.swift` | 邀请方创建码后**只依赖 WebSocket 的 `pair_success` 推送**。后端是纯内存实现，服务端重启或 WS 重连窗口会导致推送丢失 → 邀请方**永久卡在邀请码页** | 增加 HTTP `/me` **轮询兜底**：每 4 秒确认一次，最多 3 分钟，对方加入后自动进入主页 |
| 6 | `App/PairScreen.swift` | 「进入 App」按钮只调 `completePairing()`，仅把 `isPaired` 置 true，**没有设置 partner、没有订阅位置** → 进入主页后 distance 卡片永远显示「—」 | 点击时先调 `refreshPairingFromServer()` 向后端核实；未配对则提示"TA 还没输入"，不再放行 |
| 7 | `App/LoveTrackApp.swift` | `recoverRelationshipFromServer()` 是 private，外部拿不到配对状态 | 新增 `@MainActor refreshPairingFromServer() async -> Bool` 供 UI 调用 |
| 8 | `App/PairScreen.swift` | 错误直接抛 `NSError.localizedDescription`，用户看不懂 | 中文化映射：404→邀请码不存在、409→已被使用、410→已过期、超时/断网/ATS 各自提示 |

### C. 工程与辅助工具（新增）

| 文件 | 用途 |
|---|---|
| `.github/workflows/build-ios.yml` | GitHub Actions：自动编译 + 打包 ipa + 上传产物 |
| `tools/publish-github.mjs` | 不用 git 客户端，走 REST + Git Data API 发布代码 |
| `tools/watch-run.mjs` | 跟进 Actions 运行状态，逐步显示 |
| `tools/fetch-logs.mjs` | 拉取构建日志，筛出编译错误 |
| `tools/download-artifact.mjs` | 下载并校验 ipa 结构 |
| `tools/inspect-ipa.mjs` | 解析二进制 Info.plist，输出 Bundle ID / 版本 / 权限 |
| `tools/patch-project.mjs` | 用 Node 安全修改工程文件（避免 PowerShell 破坏 UTF-8） |
| `README-上传与安装.md` | 更细的安装步骤 |

---

## 使用方法

### 1. 编译（GitHub Actions，无需 Mac）

推送到 `main` 分支会自动触发，或在 Actions 页手动点 **Run workflow**。

```
Actions → Build iOS IPA (unsigned) → Run workflow
```

约 **1 分钟** 出包。产物在运行记录的 **Artifacts → `LoveTrack-unsigned-ipa`**。

> 如果自己改代码后想重新出包，直接 push 即可。仓库是 **public**，macOS runner 免费且不限分钟。

### 2. 装到 iPhone

ipa 是**未签名**的，必须先自签：

1. 电脑装 [Sideloadly](https://sideloadly.io/)（Windows/macOS 都可以）
2. iPhone 用数据线连电脑
3. 把 `.ipa` 拖进 Sideloadly，填你的 Apple ID
4. 点 Start
5. 手机上：**设置 → 通用 → VPN与设备管理 → 信任**你的开发者证书

> 免费 Apple ID 签名 **7 天过期**，到期重新签一次；同时最多 3 个自签 App。
> 详细步骤见 [`README-上传与安装.md`](README-上传与安装.md)。

### 3. 后端

本仓库**只有 iOS 客户端**。默认后端地址写在 `Network/BackendConfig.swift`：

```swift
private static let defaultBackendURL = "https://api.jiaqiya.xyz"
```

要换成自己的服务器，两种方式（**推荐第二种，不污染 git**）：

```swift
// 方式 1：直接改代码
private static let defaultBackendURL = "https://你的域名"
```

```
方式 2：Xcode scheme → Environment Variables
LOVETRACK_BACKEND_URL = https://你的域名
```

WebSocket 不用单独配，`BackendConfig.wsURL` 会自动把 `https` 转成 `wss` 并拼 `/sync`。

**后端接口约定**（当前实现对应这套）：

| 方法 | 路径 | 用途 |
|---|---|---|
| POST | `/bind` | 建邀请码 `{userId}` → `{code, expiresIn}` |
| POST | `/pair` | 用码配对 `{code, userId}` → `{inviterId, inviteeId, status}` |
| GET | `/location/:userId` | 拉最后位置（离线兜底） |
| GET | `/me?userId=` | 启动时恢复「我是否已配对」 |
| WS | `/sync?userId=` | 上行 `location_update`，下行 `partner_location` / `pair_success` |

---

## 更新记录

**每一次改动都会同步到这里：** [`CHANGELOG.md`](CHANGELOG.md)

| 版本 | 内容 |
|---|---|
| `v0.1.0-ai.3` | CI 增加 paths 过滤（改文档不再触发编译）；补全 README / NOTICE / CHANGELOG；仓库元信息 |
| `v0.1.0-ai.2` | 配对流程加固（轮询兜底 / 半配对拦截 / 错误中文化） |
| `v0.1.0-ai.1` | 首次可编译：指向已部署后端、清作者 Team ID、补 Secrets.xcconfig、加 CI |

### 更新流程（本仓库约定）

每次改动按这个顺序做，保证「代码 / 说明 / 产物」三者一致：

```bash
# 1. 改代码

# 2. 在 CHANGELOG.md 顶部加一条记录（改了什么 / 为什么 / 怎么验证的）

# 3. 同步到 GitHub（commit message 自动取 CHANGELOG 最新版本号）
$env:GITHUB_TOKEN = '你的 token'
node tools/publish-github.mjs lovetrack-ios

#    也可以手动指定说明
node tools/publish-github.mjs lovetrack-ios -m "fix: 修复 xxx"

# 4. 改的是代码/工程文件 → CI 自动编译；只改文档 → 不会触发（省 runner）

# 5. 跟进并下载新产物
node tools/watch-run.mjs Anryyanrui-ship-it/lovetrack-ios --wait
node tools/download-artifact.mjs Anryyanrui-ship-it/lovetrack-ios <artifact_id>
```

> `tools/publish-github.mjs` 走 GitHub REST + Git Data API，**不需要本地 git**。

---

## 已知限制

1. **解除配对会失败** —— `dissolveRelationship` 调用的后端路由当前实现没有对应接口（会 404）
2. **没有 App 图标** —— 原工程缺 `Assets.xcassets`，装上显示白色图标
3. **必须 iOS 17.0+** —— 地图用了 iOS 17 才有的 `Map(position:)` API
4. **后端是内存存储** —— 服务端重启后配对关系和位置全部丢失（`/me` 会返回未配对）
5. **地图可能显示"假地图"** —— `RealtimeMapScreen` 在拿不到任何坐标时，会退化成 `MiniMap`（纯 SwiftUI Canvas 手绘的示意图）。这是原设计，不是故障
6. 未做双真机全流程实测（见上文「AI 修改的可靠性边界」）

---

## 致谢

- 原始项目与全部基础业务代码：[`2000lla/lovetrack`](https://github.com/2000lla/lovetrack) 及其作者
- 原项目中的设计文档、UI 原型（`02-ui-prototype/`）、PRD 也都是原作者成果
