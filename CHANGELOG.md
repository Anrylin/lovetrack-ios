# 更新记录

本文件记录本仓库（`Anryyanrui-ship-it/lovetrack-ios`）相对上游 [`2000lla/lovetrack`](https://github.com/2000lla/lovetrack) 的每一次改动。

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号在原始项目版本后加 `-ai.N` 后缀，标明这是 AI 修改版。

> **约定**：每次改动代码，都会在本文件顶部追加一条记录，写清「改了什么 / 为什么 / 怎么验证的」。

---

## [v0.3.1-ai.1] — 2026-10-18

### 修复（未配对时仍显示假数据）

- **消息页 header**：写死「小月亮」「在线 · 最后位置 1 分钟前」「月」头像 → 改为真实 partner 名称与在线状态，未配对时显示「还没有配对 / 配对后才能互发消息」。
- **守护页 hero**：写死「小月亮」「已守护 16 小时 24 分钟」→ 改为真实 partner 名称，时长按配对天数计算。
- **守护页统计**：写死「12 次位置更新 / 2 次安全到家 / 16h 24m 守护时长」→ 改为真实今日位置上报次数、配对天数、本机电量。
- **守护页时间线**：5 条假记录（万达广场 / 山大科技园 / 已安全到家 / 开始今日守护）→ 改为真实三条：收到 TA 的位置、开始守护、我的位置已同步；无数据时显示空状态。
- **未配对时的守护页**：整页改为引导卡「还没有和 TA 配对 → 去配对」，不再展示任何守护数据。
- **紧急联系人**：3 个硬编码假联系人（妈妈 / 爸爸 / 闺蜜 小雨）→ 清空，改为本地持久化可增删；并且修好了「添加」按钮只设 `showAdd` 却从未弹窗的 bug（原来点了没反应）。
- 主页三处 `?? "小月亮"` 兜底改为 `?? "TA"`。

### 优化（地图首帧慢）

- **位置缓存**：每次收到定位就写 UserDefaults，冷启动时先读缓存点亮地图（24 小时内有效）。
- **首帧低精度加速**：冷启动时先用 `kCLLocationAccuracyKilometer` + 不做距离过滤尽快拿到第一个点，收到首点后立刻恢复档位精度（50m）。
- 定位档位进一步上调：静止心跳 `300s → 120s`、移动上报 `30s → 15s`、关闭 `pausesLocationUpdatesAutomatically`（见 v0.2.0）。

### 验证

- 二进制字符串校验：`小月亮`、`已守护 16 小时 24 分钟`、`万达广场`、`山大科技园`、`妈妈`、`闺蜜` **全部已移除**。
- 新文案 `还没有和 TA 配对`、`配对后才能开启守护…`、`还没有紧急联系人`、`用缓存位置秒开地图` **全部已进包**。
- 编译：run #19、#21 通过（run #20 因 `GuardProfile` 无统一 `desiredAccuracy` 失败，已改为按 mode 分支后修复）。

### 已知限制

- **首次安装（无缓存）仍需等 GPS 首个点**：室外约 1–3 秒，室内可能 10 秒以上。这是 iOS 硬件限制，缓存只能让第二次之后秒开。
- 对方头像暂用「TA」占位（后端 users 表有 emoji 字段，但客户端还没接）。

---

## [v0.3.0-ai.1] — 2026-10-18

新增「远程锁定」与「截图」两项能力。实现方式**经拆包 LinkUp 1.5.9 (com.youloft.houseblend) 验证**，
按其真实机制实现，未复刻其低效环节。

### 拆包依据（LinkUp 的真实做法）

- **锁机**：`Classes/Mondule/Person/LockApps/`，文案「手机已被Ta锁定」「答对问题.解锁手机」
  「设置锁定时长」「上课别玩游戏」→ 是 **App 内全屏遮罩**，`SpringBoard` 命中 0 次，不涉及系统锁屏。
- **截图**：`screenShotTa` / `screenShotMe` 命令 + `MFMessageComposeViewController` 发短信
  （正文「实时截屏 ..LinkUp」）→ 触发对方 iOS「快捷指令个人自动化」→ 拉起 `ylwatcher://screenShotCourse`
  → 对方 App 截图回传。截图 API 全是 `UIGraphicsImageRenderer` / `drawViewHierarchyInRect`（只能截自己）。
- **使用报告**：`APP使用统计.json`(176KB) / `App统计.json`(278KB) 实为 **Lottie 动画**
  （`{"v":"5.12.2","nm":"实时App使用统计"}`），不是真实统计。

### 新增

- **远程锁定**（`POST /api/lock`、`GET /api/lock/active`、`POST /api/lock/unlock` + WS `lock` / `lock:done`）
  - 发起方：主页「锁定 TA 的手机」→ 填理由 + 选时长（5/15/30/60 分钟）
  - 被锁方：WS 秒级推送 → 全屏遮罩（理由 + 倒计时 + 数学题解锁）
  - 杀掉 App 重开会通过 `/api/lock/active` 恢复遮罩
  - 明确告知用户这是 App 内限制，不是系统锁屏
- **截图（请求-同意模式）**：WS `shot:req` / `shot:resp` 转发 + `kind=image` 图片消息
  - A 点「看看 TA 的屏幕」→ B 弹「TA 想看你现在的屏幕」→ 同意后截图上传 → A 在消息里看到图片
  - 相比 LinkUp 的「短信 + 快捷指令」：无需双方配置、不花钱、1~2 秒完成、成功率更高
  - 代价：需对方每次点同意（不能偷偷截）
- 消息页支持图片气泡（base64 JPEG 解码显示）
- 后端 body 限制 `256kb → 2mb`，`kind=image` 时 `content` 上限放宽到 900000 字符

### 验证

- 锁定接口实测 **11/11 通过**（锁定、实时推送、理由与时长、查询、解锁、双方状态同步）
- 截图链路实测 **9/9 通过**（请求转发、同意回传、图片上传、实时推送、历史读取、拒绝分支）
- iOS 编译：run #16、#17、#18 全部通过

### 已知限制

- 截图只能截**本 App 界面**，截不到微信等第三方 App（iOS 系统限制，非实现问题）
- 截图需对方**在 App 前台**并点同意
- 锁定可通过杀掉 App 绕过界面，但重开会恢复；无系统级强制力

---

## [v0.2.0-ai.1] — 2026-10-17

**重大变更：后端从 lovetrack（demo 级、纯内存、无鉴权）切换到 LoveLink（账号体系 + SQLite 持久化 + JWT 鉴权）。**
接口不兼容，客户端需重新编译安装。

### 新增

- **账号体系**：注册 / 登录界面（`AuthScreen`）、token 持久化、登录后自动恢复资料与配对状态。
- **产品结构重构**：启动顺序改为「注册/登录 → 主页」，配对不再拦截启动；未配对时主页顶部显示「去配对」引导卡，点击弹出配对页。资料页与消息页不再被配对流程阻塞。
- **手机状态卡**：电量、充电状态、网络类型（Wi-Fi / 蜂窝 / 离线）、可用存储、低电量模式 —— 全部系统真实值，30 秒自动刷新。
- **今日使用统计卡**：前台分钟数、启动次数、位置上报次数、配对天数（跨天自动重置）。
- **资料编辑**：昵称与头像 emoji 可修改并保存到后端；新增退出登录。
- 网络层新增 `register` / `login` / `authedGet` / `authedJSON` / `updateMyProfile` / `sendMessage`。

### 修复

- **消息气泡文字恒为空**：`ChatMessage.content` 原为写死返回 `""` 的计算属性，且 `init(content:)` 丢弃入参。改为真实存储 `text` 字段。
- **消息页全是假数据**：`mockMessages` 硬编码 7 条。改为从 `/api/messages` 拉取、发送走后端、5 秒轮询刷新。
- **主页状态写死**：`isOnline: true` / `"iPhone 15 Pro"` / `"5G · WiFi"` / 电量默认 `0.78`。改为在线按位置新鲜度判断、机型如实标注、电量取真实值（无数据时不显示）。
- **DevMock 假伴侣与假位置**：移除启动时自动注入 mock 伴侣和济南坐标的逻辑。
- **定位刷新太慢**：标准档精度 `100m → 50m`、距离过滤 `50m → 25m`、静止心跳 `300s → 120s`、移动上报 `30s → 15s`；并关闭 `pausesLocationUpdatesAutomatically`（原来静止时系统会停止采集，对方看到的位置会长时间「冻结」）。
- **配对链路**：`createPairInvite` → `/api/pair/code`；`acceptPairInvite` → `/api/pair/request`（改为「请求 → 对方同意」两步）；`fetchMyState` → `/api/dashboard`。
- **WebSocket 协议**：路径 `/sync` → `/ws?token=`，事件名改为 LoveLink 协议（`hello` / `partner:loc` / `paired` / `unpaired` / `partner:status` / `presence`）。
- **位置上报**：优先 WebSocket `{t:"loc"}`，断线自动回退 REST `/api/location/report`。
- 资料页去除写死的「在一起 142 天」「已守护 16h」「1234 位置更新 / 567 戳一戳 / 42 守护天数 / 18 纪念日」，改为真实配对天数与手机状态。

### 变更

- 服务端：`lovetrack.service` 停止并取消开机自启，`lovelink.service` 接管 `127.0.0.1:3000`（保留可回滚）。
- nginx：新增 `/ws` 的 WebSocket 透传（原来只配了 `/sync`）。

### 验证

- 后端公网端到端 **20/20 通过**：注册 → 登录 → 配对 → 位置互相可见 → 距离 4.59 km → WSS 实时推送 → 电量状态 → 消息收发。
- iOS 分批编译验证：run #9、#10、#11、#13、#14 全部通过（run #12 因「泛型计算属性」不合法失败，已改为泛型函数后修复）。

### 已知限制

- 消息页当前是 5 秒轮询，WebSocket 的 `msg` 实时推送尚未接入。
- 对方的手机状态（电量 / 网络）尚未上报到后端，目前只显示本机状态。
- iOS 系统级「屏幕使用时间 / App 使用排行」需 Apple 特批 `com.apple.developer.family-controls` 权限，自签版本无法实现。

---

## [v0.1.0-ai.3] — 2026-10-17

### 变更

- **CI 工作流增加 `paths` 过滤**：只有代码与工程文件（`App/**`、`Network/**`、`LoveTrack.xcodeproj/**` 等）变化才自动编译；只改文档（README / CHANGELOG / NOTICE）不再触发构建，避免无意义的 runner 消耗。
- 仓库元信息补充：description 标明「AI 修改版 · 基于 2000lla/lovetrack」，新增 topics（`ios`、`swiftui`、`mapkit`、`location-tracking`、`couple-app`、`ai-modified`、`github-actions`）。

### 文档

- **新增 `README.md`**（之前缺失，GitHub 首页是空的）：包含来源归属、授权状况说明、AI 修改声明与可靠性边界、改动清单、使用方法、已知限制。
- **新增 `NOTICE.md`**：正式的版权与来源声明——原项目无 LICENSE，按「保留所有权利」处理，仅个人学习自用。
- **新增 `CHANGELOG.md`**（本文件）：此后每次改动都在此记录。
- `.gitignore` 补充 `node_modules/`、`.npmrc`、`package-lock.json`。
- 清理仓库中的 `.init` 占位文件、`.npmrc` 本地配置、`package-lock.json`。

### 验证

- run #5（含新 workflow）编译成功。
- 本次提交**只改文档**，用于验证 `paths` 过滤：预期不产生新的构建记录。

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
