import SwiftUI
import BackgroundTasks
import CoreLocation

@main
struct LoveTrackApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = AppSession()

    init() {
        // 必须在 launch 完成前注册 BGTask
        BackgroundKeepAlive.registerBackgroundTasks()
        // MapKit 不需要手动初始化,系统自带
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(session.relationshipStore)
                .environmentObject(session.guardSettings)
                .task {
                    await session.bootstrap()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                session.handleEnterBackground()
            case .active:
                session.handleEnterForeground()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

/// App 全局依赖容器。
@MainActor
final class AppSession: ObservableObject {
    let realtime: RealtimeSyncServiceProtocol
    let locationManager: LocationManager
    let relationshipStore: RelationshipStore
    let guardSettings: GuardSettings

    @Published var currentUser: User
    @Published var authState: LocationManager.AuthState = .notDetermined
    @Published var lastLocation: CLLocation?
    @Published var isReady: Bool = false
    @Published var isPaired: Bool = false
    @Published var currentRelationship: Relationship?
    /// 是否已登录（LoveLink 账号体系）；false → 显示 AuthScreen
    @Published var isLoggedIn: Bool = false
    /// 控制「配对」弹层显示（由主页按钮触发）
    @Published var showPairSheet: Bool = false
    /// 我的头像 emoji（来自账号，可在「我的」页修改）
    @Published var myEmoji: String = "🐰"
    /// 我的账号名（注册时定的，不随昵称变化）
    @Published var myAccount: String = ""
    /// 当前生效的锁定（被对方锁 App 时非 nil，RootView 用它盖全屏遮罩）
    @Published var activeLock: LockState?
    /// 收到对方的截图请求（RootView 弹确认框）
    @Published var incomingShotRequest = false
    /// 截图相关提示
    @Published var shotNotice: String?
    /// 收到对方的紧急提醒
    @Published var incomingSOS: SOSInfo?

    struct SOSInfo: Equatable {
        let nickname: String
        let lat: Double?
        let lng: Double?
        let at: Date
    }

    /// 锁定状态
    struct LockState: Equatable {
        let id: String
        let reason: String
        let untilAt: Date
    }

    private var locationTask: Task<Void, Never>?
    private var partnerLocationTask: Task<Void, Never>?
    private var partnerHttpPollTask: Task<Void, Never>?
    private var pauseCheckTask: Task<Void, Never>?

    init() {
        // 用稳定的 userId（生产应该用 Apple ID / UUID 持久化到 Keychain）
        let storedId = UserDefaults.standard.string(forKey: "lovetrack.userId") ?? UUID().uuidString
        UserDefaults.standard.set(storedId, forKey: "lovetrack.userId")
        let me = User(id: storedId, displayName: "我")
        self.currentUser = me
        let lm = LocationManager.shared
        self.locationManager = lm
        // 用 HTTP 后端版（对接 05-backend Node.js）
        let sync: RealtimeSyncServiceProtocol = HTTPRealtimeSyncService(userId: storedId)
        self.realtime = sync
        self.relationshipStore = RelationshipStore(me: me, realtime: sync)
        self.guardSettings = GuardSettings()

        // 锁机回调：被对方锁定时弹全屏遮罩（只锁本 App，不涉及系统）
        if let http = sync as? HTTPRealtimeSyncService {
            http.onLockReceived = { [weak self] id, reason, untilAt in
                Task { @MainActor in
                    self?.activeLock = LockState(
                        id: id,
                        reason: reason,
                        untilAt: Date(timeIntervalSince1970: untilAt / 1000)
                    )
                    Log.info("AppSession", "🔒 收到锁定：\(reason)")
                }
            }
            http.onLockCleared = { [weak self] in
                Task { @MainActor in
                    self?.activeLock = nil
                    Log.info("AppSession", "🔓 锁定已解除")
                }
            }
            http.onShotRequest = { [weak self] in
                Task { @MainActor in
                    self?.incomingShotRequest = true
                    Log.info("AppSession", "📸 收到对方的截图请求")
                }
            }
            http.onShotResponse = { [weak self] accept in
                Task { @MainActor in
                    self?.shotNotice = accept ? "TA 同意了，正在截图…" : "TA 拒绝了这次请求"
                    Log.info("AppSession", "对方回应截图：\(accept ? "同意" : "拒绝")")
                }
            }
            http.onPartnerProfile = { [weak self] user in
                Task { @MainActor in
                    guard let self else { return }
                    let nickname = user["nickname"] as? String ?? "TA"
                    let pid = (user["id"] as? String) ?? self.relationshipStore.partner?.id ?? ""
                    self.relationshipStore.partner = User(id: pid, displayName: nickname)
                    Log.info("AppSession", "对方资料已同步：\(nickname)")
                }
            }
            http.onSOS = { [weak self] msg in
                Task { @MainActor in
                    guard let self else { return }
                    let at = msg["at"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
                    self.incomingSOS = SOSInfo(
                        nickname: msg["nickname"] as? String ?? "TA",
                        lat: msg["lat"] as? Double,
                        lng: msg["lng"] as? Double,
                        at: Date(timeIntervalSince1970: at / 1000)
                    )
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    Log.warn("AppSession", "🚨 收到紧急提醒")
                }
            }
        }

        // 监听 WebSocket 推送的 pair_success：对方加入 → 自动跳转主页
        if let http = sync as? HTTPRealtimeSyncService {
            self.isLoggedIn = http.isLoggedIn
            http.onPairSuccess = { [weak self] inviteeId in
                Task { @MainActor in
                    guard let self else { return }
                    self.isPaired = true
                    self.relationshipStore.partner = User(id: inviteeId, displayName: "伴侣")
                    self.relationshipStore.isPaired = true
                    // 🐛 BUG FIX: inviter 流程下,store.relationship 卡在 pending (userB="")
                    // 导致 pollPartnerLocationOnce guard 在 partnerId.isEmpty 处永远返回,
                    // lastKnownPartnerLocation 一直是 WS 重连时的陈旧数据,UI 显示"对方不正确"。
                    // 这里构造一个 active Relationship 并 applyRelationship,触发订阅 + 修正 polling 路径。
                    let inviterId = self.currentUser.id
                    let pendingRel = self.relationshipStore.relationship
                    let activeRel = Relationship(
                        id: pendingRel?.id ?? "rel_\(inviterId)_\(inviteeId)",
                        userA: inviterId,
                        userB: inviteeId,
                        status: .active,
                        pairedAt: pendingRel?.pairedAt ?? Date()
                    )
                    Task { @MainActor in
                        await self.relationshipStore.startObservingPartnerWithRelationship(activeRel)
                    }
                    self.relationshipStore.relationship = activeRel
                    Log.info("AppSession", "pair_success → auto-transitioning to main, inviteeId=\(inviteeId), relationship upgraded to active")
                    // 配对成功后立即拉一次对方位置（不等 15s 轮询）
                    Task { await self.pollPartnerLocationOnce() }
                }
            }
        }
    }

    @MainActor
    func completePairing(relationship: Relationship? = nil) {
        isPaired = true
        if let rel = relationship {
            currentRelationship = rel
        }
        Log.info("AppSession", "completePairing called, isPaired=\(isPaired)")
    }

    /// 登录/注册成功后调用：写入用户信息并进入主页
    @MainActor
    func markLoggedIn(_ result: HTTPRealtimeSyncService.AuthResult) {
        isLoggedIn = true
        currentUser = User(id: result.userId, displayName: result.nickname)
        myEmoji = result.emoji
        myAccount = result.account
        if let pid = result.partnerId, !pid.isEmpty {
            relationshipStore.partner = User(id: pid, displayName: result.partnerName ?? "伴侣")
            relationshipStore.isPaired = result.paired
        }
        isPaired = result.paired
        Log.info("AppSession", "已登录：\(result.nickname)（\(result.userId)）已配对=\(result.paired) 配对码=\(result.coupleCode ?? "-")")
    }

    /// 退出登录
    @MainActor
    func signOutAccount() {
        (realtime as? HTTPRealtimeSyncService)?.signOut()
        isLoggedIn = false
        isPaired = false
        relationshipStore.isPaired = false
        relationshipStore.partner = nil
        relationshipStore.relationship = nil
        activeLock = nil
        Log.info("AppSession", "已退出登录")
    }

    /// 回应对方的截图请求（同意则立刻截图上传）
    @MainActor
    func respondToShot(accept: Bool) async {
        incomingShotRequest = false
        guard let http = realtime as? HTTPRealtimeSyncService else { return }

        if accept {
            if let b64 = AppSession.captureScreenBase64() {
                do {
                    try await http.sendImage(b64)
                    shotNotice = "已把当前屏幕发给 TA"
                    Log.info("AppSession", "📸 截图已发送")
                } catch {
                    shotNotice = "截图发送失败：\(error.localizedDescription)"
                    Log.error("AppSession", "截图发送失败：\(error)")
                }
            } else {
                shotNotice = "截图失败（系统限制）"
            }
        }
        http.sendShotResponse(accept: accept)
    }

    /// 截取当前 App 窗口 → 压缩成 base64 JPEG（约 100KB）
    static func captureScreenBase64(maxWidth: CGFloat = 800, quality: CGFloat = 0.55) -> String? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let shot = renderer.image { ctx in
            window.layer.render(in: ctx.cgContext)
        }
        let scale = min(1, maxWidth / max(shot.size.width, 1))
        let target = CGSize(width: shot.size.width * scale, height: shot.size.height * scale)
        let r2 = UIGraphicsImageRenderer(size: target)
        let resized = r2.image { _ in shot.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)?.base64EncodedString()
    }

    /// 答对题后解锁（通知后端，让双方状态一致）
    @MainActor
    func unlockCurrentLock() async {
        guard let lock = activeLock else { return }
        guard let http = realtime as? HTTPRealtimeSyncService else {
            activeLock = nil
            return
        }
        do {
            try await http.unlockDevice(lockId: lock.id)
            activeLock = nil
            Log.info("AppSession", "已解锁 \(lock.id)")
        } catch {
            // 网络失败也先在本地解除，避免用户被永久困住
            activeLock = nil
            Log.warn("AppSession", "解锁请求失败，已在本地解除：\(error.localizedDescription)")
        }
    }

    /// 启动时检查自己是否处于被锁状态（App 被杀掉重开后仍要恢复遮罩）
    @MainActor
    func refreshActiveLock() async {
        guard let http = realtime as? HTTPRealtimeSyncService, http.isLoggedIn else { return }
        do {
            guard let obj = try await http.fetchActiveLock() else {
                activeLock = nil
                return
            }
            if let id = obj["id"] as? String,
               let untilAt = obj["untilAt"] as? TimeInterval {
                activeLock = LockState(
                    id: id,
                    reason: obj["reason"] as? String ?? "乖乖听话",
                    untilAt: Date(timeIntervalSince1970: untilAt / 1000)
                )
                Log.info("AppSession", "恢复锁定状态 \(id)")
            }
        } catch {
            Log.warn("AppSession", "查询锁定状态失败：\(error.localizedDescription)")
        }
    }

    /// 主动向后端确认「我是否已配对」并恢复完整状态，返回最新结果。
    ///
    /// 用处有两个：
    /// 1. inviter 停在「你的邀请码」页面等对方加入时轮询兜底 —— WS 的 pair_success 可能漏推
    ///    （后端 in-memory 重启、网络抖动都会导致），光靠推送会让 A 永远卡住。
    /// 2. PairScreen 点「进入 App」前先核实一次，避免进入"半配对"状态
    ///    （isPaired=true 但 partner 为空、没有订阅位置）。
    @MainActor
    @discardableResult
    func refreshPairingFromServer() async -> Bool {
        await recoverRelationshipFromServer()
        return isPaired
    }

    func bootstrap() async {
        // 0. 检查暂停是否到期
        _ = guardSettings.checkPauseExpiry()

        // 0.5 首帧加速：先用上次缓存的位置点亮地图，GPS 首个点到了会自动覆盖
        if lastLocation == nil, let cached = LocationManager.loadCachedLocation() {
            lastLocation = cached
            Log.info("AppSession", "⚡️ 用缓存位置秒开地图：\(cached.coordinate.latitude), \(cached.coordinate.longitude)，缓存于 \(Int(Date().timeIntervalSince(cached.timestamp)))s 前")
        }

        // 1. 注册定位
        authState = await locationManager.requestAuthorization()
        // 2. 启动后台保活
        await BackgroundKeepAlive.shared.start(locationManager: locationManager)
        // 3. 提前连接 WebSocket（即使还没配对也连，位置才能流出去；后端会忽略 partner 推送）
        if let http = realtime as? HTTPRealtimeSyncService {
            await http.bootstrapConnect()
        }
        // 3.5 从后端恢复关系状态（in-memory 存储 → App 启动必须查一次）
        //     修这个之前: 重启 App 后 PairScreen 永远卡住,因为 WS pair_success 漏推
        await recoverRelationshipFromServer()
        // 4. 订阅定位 → 同步到云（不管 mode 是什么都要订阅，因为 mode=off 时会 stop，事件不会来）
        locationTask?.cancel()
        locationTask = Task { [weak self] in
            guard let self = self else { return }
            let stream = await self.locationManager.events()
            for await event in stream {
                let point = LocationPoint(
                    userId: self.currentUser.id,
                    lat: event.location.coordinate.latitude,
                    lon: event.location.coordinate.longitude,
                    altitude: event.location.altitude,
                    horizontalAccuracy: event.location.horizontalAccuracy,
                    verticalAccuracy: event.location.verticalAccuracy,
                    speed: event.location.speed,
                    course: event.location.course,
                    timestamp: event.location.timestamp,
                    battery: event.battery,
                    source: mapSource(event.mode),
                    sessionId: event.sessionId
                )
                try? await self.realtime.uploadPoint(point)
                UsageStats.countReport()
                self.lastLocation = event.location
                // 🐛 Bug 排查:userId=自己,坐标=GPS,标记为"我"上传。
                Log.info("AppSession", "📤 我上传: userId=\(point.userId) lat=\(point.lat) lon=\(point.lon) mode=\(event.mode.rawValue) hp=\(Int(point.horizontalAccuracy))m")
            }
        }
        // 5. 按用户选的档位启动定位
        applyGuardMode()
        // 6. 订阅 partner 位置流（把对方位置更新到 store）
        startObservingPartnerLocation()
        // 7. HTTP 兜底轮询：WebSocket 断了也能拉
        startPartnerHttpPolling()
        // 8. 暂停到期检查（每分钟跑一次）
        startPauseCheckLoop()
        isReady = true
    }

    /// 启动时从后端拉一次"我的关系状态",避免 server 重启 / App 重启后 PairScreen 卡死。
    /// 后端 in-memory 存储,Server 进程死了数据就没了,但 iOS 这边的 PairScreen 状态需要主动同步。
    @MainActor
    private func recoverRelationshipFromServer() async {
        guard let http = realtime as? HTTPRealtimeSyncService else { return }
        do {
            guard let state = try await http.fetchMyState() else {
                Log.info("AppSession", "recover: not paired (clean start)")
                return
            }
            Log.info("AppSession", "recover: ✅ paired with \(state.partnerId), restoring session")
            currentRelationship = state.relationship
            relationshipStore.relationship = state.relationship
            relationshipStore.partner = User(id: state.partnerId, displayName: "伴侣")
            relationshipStore.isPaired = true
            isPaired = true
            http.setPartnerKey(state.partnerId)
            if let loc = state.lastKnownPartnerLocation {
                relationshipStore.refreshPartnerLocation(loc)
            }
            // 触发 RelationshipStore 订阅
            await relationshipStore.startObservingPartner()
        } catch {
            Log.warn("AppSession", "recover: failed (offline? \(error))")
        }
    }

    /// 根据 guardSettings 把 LocationManager 切到对应档位。
    func applyGuardMode() {
        let profile = locationProfile(for: guardSettings.mode)
        if guardSettings.isPaused || guardSettings.mode == .off {
            Task { await locationManager.pause() }
            Log.info("AppSession", "🛑 定位已暂停 (mode=\(guardSettings.mode.rawValue), isPaused=\(guardSettings.isPaused))")
        } else {
            Task { await locationManager.switchProfile(to: profile) }
            Log.info("AppSession", "▶️ 定位已启动 (profile=\(profile.rawValue))")
        }
    }

    private func locationProfile(for mode: GuardMode) -> LocationManager.GuardProfile {
        switch mode {
        case .off:       return .off
        case .standard:  return .standard
        case .realtime:  return .realtime
        }
    }

    /// 用户从设置页切换档位 / 暂停 / 恢复时调用。
    func handleGuardChange() {
        Log.info("AppSession", "守护设置变更: mode=\(guardSettings.mode.rawValue), isPaused=\(guardSettings.isPaused)")
        applyGuardMode()
    }

    private func startPauseCheckLoop() {
        pauseCheckTask?.cancel()
        pauseCheckTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)  // 60s
                let expired = await MainActor.run { self.guardSettings.checkPauseExpiry() }
                if expired {
                    Log.info("AppSession", "暂停到期，自动恢复共享")
                    await MainActor.run { self.applyGuardMode() }
                }
            }
        }
    }

    /// 订阅对方位置 → 推到 RelationshipStore
    private func startObservingPartnerLocation() {
        partnerLocationTask?.cancel()
        partnerLocationTask = Task { [weak self] in
            guard let self = self else { return }
            for await point in self.realtime.observePartnerLocation(userId: "partner") {
                await MainActor.run {
                    // 通过 store 更新对方位置（store 内部已经维护 lastKnownPartnerLocation）
                    // 这里直接 refresh 触发 store 内的订阅
                    self.relationshipStore.refreshPartnerLocation(point)
                }
            }
        }
    }

    /// HTTP 轮询兜底：前台每 15s 拉一次对方位置（WebSocket 断了也能拿到）。
    /// 关键场景：App 从后台切回前台、WebSocket 重连中、首次启动对方还没上报。
    private func startPartnerHttpPolling() {
        partnerHttpPollTask?.cancel()
        partnerHttpPollTask = Task { [weak self] in
            guard let self = self else { return }
            // 启动先等 2s 让 pairing 先稳定（避免循环依赖）
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            while !Task.isCancelled {
                await self.pollPartnerLocationOnce()
                try? await Task.sleep(nanoseconds: 15_000_000_000)  // 15s
            }
        }
        Log.info("AppSession", "partner HTTP 轮询启动 (15s/次)")
    }

    @MainActor
    private func pollPartnerLocationOnce() async {
        guard let store = self.relationshipStore.relationship,
              let http = self.realtime as? HTTPRealtimeSyncService else {
            // 还没配对，不拉
            return
        }
        // 拿对方的 userId
        let partnerId: String
        if store.userA == self.currentUser.id {
            partnerId = store.userB
        } else if store.userB == self.currentUser.id {
            partnerId = store.userA
        } else {
            // pending 关系 / 异常
            return
        }
        guard !partnerId.isEmpty else { return }

        // HTTP 拉（service 内部会更新缓存 + 推给订阅者，触发 store.refreshPartnerLocation）
        do {
            _ = try await http.fetchPartnerLocation(userId: partnerId)
        } catch {
            Log.warn("AppSession", "HTTP 拉取对方位置失败: \(error)")
        }
    }

    func handleEnterForeground() {
        // 省电模式：回到前台要把定位重新拉起来
        if guardSettings.powerSaving {
            Log.info("AppSession", "省电模式：回到前台，恢复定位")
            applyGuardMode()
        }
        Task { await locationManager.handleAppForeground() }
        // 切回前台立即拉一次对方位置（不等 15s 轮询）
        Task { await pollPartnerLocationOnce() }
        // 确保轮询在跑
        if partnerHttpPollTask == nil || partnerHttpPollTask?.isCancelled == true {
            startPartnerHttpPolling()
        }
    }

    func handleEnterBackground() {
        // 省电模式：进入后台直接停采，只在前台共享位置
        if guardSettings.powerSaving {
            Log.info("AppSession", "省电模式：进入后台，停止定位")
            Task { await locationManager.stop() }
            return
        }
        Task { await locationManager.handleAppBackground() }
    }

    private func mapSource(_ mode: LocationManager.TrackingMode) -> Source {
        switch mode {
        case .foreground, .background: return .gps
        case .significantChange: return .significantChange
        case .off: return .gps
        }
    }
}

/// 根视图（极简占位）。
struct RootView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    var body: some View {
        ZStack {
            Group {
                if !session.isLoggedIn {
                    // 未登录：先注册 / 登录（LoveLink 账号体系）
                    AuthScreen()
                } else {
                    // 已登录：直接进主页。配对不再拦截启动流程，
                    // 改由主页顶部的「配对」按钮触发（session.showPairSheet）。
                    mainTabs
                        .sheet(isPresented: $session.showPairSheet) {
                            PairScreen()
                        }
                        .alert("截图提示", isPresented: Binding(
                            get: { session.shotNotice != nil },
                            set: { if !$0 { session.shotNotice = nil } }
                        )) {
                            Button("好") { session.shotNotice = nil }
                        } message: {
                            Text(session.shotNotice ?? "")
                        }
                }
            }

            // 被对方锁定：全屏遮罩盖住一切（只锁本 App，不涉及系统锁屏）
            if let lock = session.activeLock {
                LockOverlay(lock: lock) {
                    await session.unlockCurrentLock()
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .alert("TA 想看你现在的屏幕", isPresented: $session.incomingShotRequest) {
            Button("拒绝", role: .cancel) {
                Task { await session.respondToShot(accept: false) }
            }
            Button("同意") {
                Task { await session.respondToShot(accept: true) }
            }
        } message: {
            Text("同意后会截图当前 App 界面发给 TA。一次性授权，不会持续录屏。")
        }
        .alert("🚨 紧急提醒", isPresented: Binding(
            get: { session.incomingSOS != nil },
            set: { if !$0 { session.incomingSOS = nil } }
        )) {
            Button("知道了") { session.incomingSOS = nil }
        } message: {
            Text(sosMessageText)
        }
    }

    private var sosMessageText: String {
        guard let sos = session.incomingSOS else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let t = f.string(from: sos.at)
        if sos.lat != nil {
            return "\(sos.nickname) 在 \(t) 发出紧急提醒，已附带位置，去地图看看 TA 在哪。"
        }
        return "\(sos.nickname) 在 \(t) 发出紧急提醒（未附带位置）。"
    }

    private var mainTabs: some View {
        // 4 tabs 完整 UI（守护 / 位置 / 消息 / 我的）
        AppTabView()
    }
}

// MARK: - 锁定遮罩

/// 被 Ta 锁定时的全屏遮罩。
/// 说明：这是 App 内的界面遮罩，不是系统锁屏 —— iOS 不允许普通 App 锁设备。
/// 参照 LinkUp 的做法：显示「手机已被 Ta 锁定」+ 理由 + 倒计时，答对数学题解锁。
struct LockOverlay: View {
    let lock: AppSession.LockState
    let onUnlock: () async -> Void

    @State private var a = Int.random(in: 13...49)
    @State private var b = Int.random(in: 11...39)
    @State private var answer = ""
    @State private var error: String?
    @State private var now = Date()
    @State private var working = false

    private var remainSeconds: Int {
        max(0, Int(lock.untilAt.timeIntervalSince(now)))
    }

    private var remainText: String {
        let s = remainSeconds
        if s <= 0 { return "00:00" }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.09, blue: 0.20),
                    Color(red: 0.30, green: 0.12, blue: 0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Text("🔒").font(.system(size: 68))

                Text("手机已被 Ta 锁定")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(lock.reason)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text(remainText)
                    .font(.system(size: 42, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)

                Text(remainSeconds <= 0 ? "时间到，可以解锁了" : "答对这道题就能提前解锁")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 10) {
                    Text("\(a) + \(b) =")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    TextField("?", text: $answer)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .frame(width: 96)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.top, 4)

                if let e = error {
                    Text(e)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if working {
                            ProgressView().tint(.black)
                        } else {
                            Text("解锁").font(.headline)
                        }
                    }
                    .frame(maxWidth: 200)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                }
                .disabled(working)

                Text("这是 App 内的使用限制，不是系统锁屏；\n划掉 App 重开仍会继续锁定。")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 32)
                    .padding(.top, 6)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { t in
            now = t
        }
    }

    @MainActor
    private func submit() async {
        guard let n = Int(answer.trimmingCharacters(in: .whitespaces)) else {
            error = "请输入数字"
            return
        }
        guard n == a + b else {
            error = "答案不对，再想想～"
            answer = ""
            a = Int.random(in: 13...49)
            b = Int.random(in: 11...39)
            return
        }
        working = true
        error = nil
        await onUnlock()
        working = false
    }
}

/// 开发期 mock — 在 DEBUG 编译、且没配对时,自动给一份假伴侣+假位置,方便看 UI
enum DevMock {
    @MainActor
    static func bootstrapIfNeeded(session: AppSession, store: RelationshipStore) {
        guard !session.isPaired, !store.isPaired else { return }

        // 1. 标记配对完成
        session.isPaired = true

        // 2. 注入 mock 伴侣
        let mockPartnerId = "mock-partner-001"
        let mockPartner = User(
            id: mockPartnerId,
            displayName: "小月亮",
            avatarURL: nil
        )

        // 3. 注入 mock 位置（济南历城区 — 跟原型地图一致）
        let mockLocation = LocationPoint(
            userId: mockPartnerId,
            lat: 36.6512,          // 历城区
            lon: 117.1201,
            altitude: nil,
            horizontalAccuracy: 5.0,
            verticalAccuracy: nil,
            speed: 0,
            course: 0,
            timestamp: Date().addingTimeInterval(-60), // 1 分钟前
            receivedAt: Date(),
            battery: BatteryInfo(level: 0.78, isCharging: false, isLowPower: false),
            source: .gps,
            sessionId: "mock-session"
        )

        // 4. 注入"我"的当前位置（山大科技产业园 — 跟伴侣距离 1.2km）
        let myLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 36.6640, longitude: 117.1280),
            altitude: 0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: -1,
            course: 0,
            speed: 0,
            timestamp: Date()
        )

        store.partner = mockPartner
        store.isPaired = true
        store.lastKnownPartnerLocation = mockLocation
        session.lastLocation = myLocation

        Log.info("DevMock", "✅ mock 伴侣 + 位置已注入,直接进主页调试")
    }
}

// RealtimeMapScreen 已在 App/RealtimeMapScreen.swift 定义（高保真复刻原型）

struct TrackPlaybackScreen: View {
    @EnvironmentObject var session: AppSession

    var body: some View {
        let vm = TrackPlaybackViewModel(sync: session.realtime)
        return TrackPlaybackView(viewModel: vm)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject var session: AppSession

    var body: some View {
        Form {
            // MARK: - 守护模式
            Section {
                ForEach(GuardMode.allCases) { mode in
                    Button {
                        guardSettings.mode = mode
                        session.handleGuardChange()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .font(.title2)
                                .foregroundStyle(mode.accentColor)
                                .frame(width: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if guardSettings.mode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(mode.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("守护模式")
            } footer: {
                Text("默认「标准守护」是保守档：后台静止时 5 分钟心跳一次。开启「实时守护」会增加约 15% 的电量消耗。")
            }

            // MARK: - 一键暂停
            if !guardSettings.isPaused && guardSettings.mode != .off {
                Section {
                    Button(role: .destructive) {
                        guardSettings.pauseForOneHour()
                        session.handleGuardChange()
                    } label: {
                        Label("暂停共享 1 小时", systemImage: "pause.circle")
                    }
                    Button(role: .destructive) {
                        guardSettings.pauseUntilMorning()
                        session.handleGuardChange()
                    } label: {
                        Label("暂停到明早 8 点", systemImage: "moon.stars")
                    }
                } header: {
                    Text("暂停共享")
                } footer: {
                    Text("暂停期间你看不到 TA，TA 也看不到你。后台定位会停止，电量恢复正常。")
                }
            } else if let until = guardSettings.pausedUntil {
                Section {
                    HStack {
                        Image(systemName: "pause.circle.fill")
                            .foregroundStyle(.orange)
                        Text("已暂停到 \(formatted(until))")
                        Spacer()
                    }
                    Button("立即恢复") {
                        guardSettings.resume()
                        session.handleGuardChange()
                    }
                } header: {
                    Text("暂停中")
                }
            }

            // MARK: - 权限
            Section("权限") {
                Text("定位权限: \(authLabel)")
                Button("请求 Always 权限") {
                    Task { _ = await session.locationManager.requestAuthorization() }
                }
            }

            // MARK: - 关系
            Section("关系") {
                if session.relationshipStore.isPaired {
                    Button("解除关系", role: .destructive) {
                        Task {
                            try? await session.relationshipStore.dissolve()
                            session.isPaired = false
                        }
                    }
                } else {
                    Text("尚未配对")
                }
            }

            // MARK: - 调试
            Section("调试") {
                LabeledContent("userId") {
                    Text(session.currentUser.id)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("后端") {
                    Text(BackendConfig.baseURL.absoluteString)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                LabeledContent("当前 profile") {
                    Text(currentProfileLabel)
                        .font(.caption.monospaced())
                }
            }
        }
        .navigationTitle("设置")
    }

    private var guardSettings: GuardSettings { session.guardSettings }

    private var authLabel: String {
        switch session.authState {
        case .notDetermined: return "未决定"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .whenInUse: return "使用期间"
        case .always: return "始终"
        }
    }

    private var currentProfileLabel: String {
        if guardSettings.isPaused { return "已暂停" }
        if guardSettings.mode == .off { return "off" }
        if guardSettings.mode == .standard { return "standard" }
        return "realtime"
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
