# 更新记录

本文件记录本仓库（`Anryyanrui-ship-it/lovetrack-ios`）相对上游 [`2000lla/lovetrack`](https://github.com/2000lla/lovetrack) 的每一次改动。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号在原始项目版本后加 `-ai.N` 后缀，标明这是 AI 修改版。

> **约定**：每次改动代码，都会在本文件顶部追加一条记录，写清「改了什么 / 为什么 / 怎么验证的」。

---

## [v0.1.0-ai.2] — 2026-10-17

### 修复

- **邀请方永久卡在邀请码页**
  - 现象：A 生成邀请码后，B 输入并绑定成功，但 A 的界面一直停在「你的邀请码」，不进入主页。
  - 原因：A 侧完全依赖 WebSocket 的 `pair_success` 推送。后端是纯内存实现，服务端重启、WS 断线重连窗口期、NAT 超时都会导致这条推送丢失，而客户端没有任何兜底。
  - 修复：在 `PairScreen` 增加 HTTP `/me` 轮询兜底，每 4 秒确认一次配对状态，最多 3 分钟；检测到已配对立即自动进入主页。

- **「进入 App」导致半配对状态**
  - 现象：A 不等对方加入就点「进入 App」，进入主页后距离卡片永远显示「—」，看不到对方位置。
  - 原因：该按钮只调 `session.completePairing()`，仅把 `isPaired` 置为 true，**没有设置 partner、也没有启动位置订阅**。
  - 修复：点击时先调 `refreshPairingFromServer()` 向后端核实；已配对则完整恢复状态，未配对则提示"TA 还没输入邀请码"并拦下。

- **错误提示不可读**
  - 现象：报错直接显示 `The operation couldn't be completed. (LoveTrack.HTTPRealtimeSyncService.ServiceError error 0.)`
  - 修复：按状态码/错误码翻译成中文——404 邀请码不存在、409 已被使用、410 已过期、超时/断网/ATS 拦截分别提示。

### 新增

- `AppSession.refreshPairingFromServer() async -> Bool`（`App/LoveTrackApp.swift`）：公开的配对状态恢复方法，供 UI 主动核实。
- `PairScreen.friendlyMessage(_:)`：错误中文化映射。
- `PairScreen.startWaitingForPartner()` / `enterAppNow()`：轮询兜底与进入前核实。

### 修改

- `App/PairScreen.swift`：引入 `Foundation`；新增 `@State pollTask`；`createView` 增加 `onAppear` / `onDisappear` 生命周期管理。

### 验证

- GitHub Actions run #2 编译**失败**：`PairScreen.swift:371 switch must be exhaustive`（`ServiceError` 还有 `.connectionClosed` 未覆盖）。
- 补上该 case 后 run #3 **编译成功**，耗时 1m13s。
- 产物校验：arm64 真机架构、744.0 KB、`com.lovetrack.app`、`MinimumOSVersion 17.0`、未签名。
- 二进制内已确认包含新字符串：「TA 还没输入邀请码」「邀请码已过期」「连不上服务器」；旧文案「创建失败:」已消失。

---

## [v0.1.0-ai.1] — 2026-10-17

首次让工程**真正能编译出 ipa**。原始工程直接 clone 下来是编不过的。

### 修复

- **`Secrets.xcconfig` 缺失导致编译失败**
  - `project.pbxproj` 把它作为 `baseConfigurationReference` 引用，但原仓库 `.gitignore` 忽略了它，文件实际不存在 → `Build input file cannot be found`。
  - 新建空模板文件，并在 `.gitignore` 中显式说明「必须提交」。

- **原作者的签名 Team ID 无法使用**
  - `DEVELOPMENT_TEAM = 2CG772X26Z`（3 处，含 `TargetAttributes.DevelopmentTeam`）是原作者的个人 Team，其他人没有权限签名。
  - 全部清空，CI 改用 `CODE_SIGNING_ALLOWED=NO` 无签名编译。

- **后端地址是占位符**
  - `BackendConfig.swift` 中为 `http://YOUR_SERVER_IP:3000`，装到手机上连不到任何服务器。
  - 改为已部署的 `https://api.jiaqiya.xyz`（香港服务器 + Cloudflare + Let's Encrypt）。

### 新增

- `.github/workflows/build-ios.yml`：macOS runner 上无签名编译 → 打包 `Payload/LoveTrack.app` → 输出 `LoveTrack-unsigned.ipa` → 上传 Artifact。含 AppIcon 失败重试、编译日志上传、产物 Info.plist 打印。
- `tools/` 辅助脚本（不在 App 内运行，只用于发布与校验）：
  - `publish-github.mjs`（走 Git Data API 发布，无需 git 客户端）
  - `watch-run.mjs`（跟进 Actions 状态）
  - `fetch-logs.mjs`（拉日志筛编译错误）
  - `download-artifact.mjs`（下载并校验 ipa 结构）
  - `inspect-ipa.mjs`（解析二进制 Info.plist）
  - `patch-project.mjs`（用 Node 改工程文件，规避 PowerShell 破坏 UTF-8 中文）
- `README.md`、`README-上传与安装.md`、`NOTICE.md`。

### 验证

- GitHub Actions run #1 **编译成功**，耗时 54s。
- 产物校验：arm64 真机架构（非模拟器版）、731.6 KB、`com.lovetrack.app`、iOS 17.0、`UIBackgroundModes` 含 `location`、未签名。
- 后端侧端到端验证 `tools/e2e-public.mjs`：11/11 通过（建码 → 配对 → WSS 连接 → 位置实时转发 → 心跳 → REST 离线查询）。

---

## 附：未做但已知的缺口

按优先级排列，后续可能补：

1. **解除配对**：`dissolveRelationship` 会调后端一个当前未实现的接口，导致 404。
2. **App 图标**：原工程缺 `Assets.xcassets`，`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 无对应资源，装上显示白色图标。
3. **后端持久化**：当前后端纯内存，重启即丢配对关系与位置。
4. **鉴权**：后端无 token 校验，任何人知道域名即可伪造 `userId` 读取位置。
5. **Swift 6 兼容**：编译日志中有 `NSLock.lock() is unavailable from asynchronous contexts` 警告，Swift 6 语言模式下会升级为错误。
