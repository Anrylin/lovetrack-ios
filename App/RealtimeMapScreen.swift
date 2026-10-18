import SwiftUI
import CoreLocation

/// 实时定位主页 — 复刻原型 love-location.html
/// 结构: Status bar → PartnerHero → 地图(高德真地图/MiniMap Canvas) → DistanceCard → PokeGrid → QuickCards → BottomNav
public struct RealtimeMapScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore
    @EnvironmentObject var guardSettings: GuardSettings

    @State private var locationEnabled: Bool = true
    @State private var toastMessage: String?
    @State private var toastIcon: String?
    /// 地图样式（经典 / 卫星 / 混合），从本地恢复
    @State private var mapStyle: MapKitView.MapStyleOption = {
        let raw = UserDefaults.standard.string(forKey: "map.style") ?? ""
        return MapKitView.MapStyleOption(rawValue: raw) ?? .standard
    }()
    @State private var showTracks = false
    @State private var showLockSheet = false
    @State private var lockReason = ""
    @State private var lockMinutes = 30
    @State private var locking = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            backgroundLayer
            contentScroll
            toastLayer
            // 底部导航由 AppTabView 统一管理
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showLockSheet) { lockSheet }
        .sheet(isPresented: $showTracks) {
            TrackSheet(realtime: session.realtime) { showTracks = false }
        }
    }

    // MARK: - Layers

    private var backgroundLayer: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                stops: [
                    .init(color: Color(red: 1.00, green: 0.84, blue: 0.91).opacity(0.55), location: 0.0),
                    .init(color: .clear, location: 0.5),
                    .init(color: Color(red: 0.91, green: 0.84, blue: 1.00).opacity(0.55), location: 1.0),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            backgroundStickers
        }
        .ignoresSafeArea()
    }

    private var backgroundStickers: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .font(.system(size: 24))
                .foregroundColor(Theme.primary)
                .opacity(0.10)
                .offset(x: -140, y: -320)
            Image(systemName: "sparkle")
                .font(.system(size: 20))
                .foregroundColor(Theme.violet)
                .opacity(0.12)
                .offset(x: 140, y: -180)
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(Theme.primary)
                .opacity(0.10)
                .offset(x: -150, y: 80)
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundColor(Theme.violet)
                .opacity(0.12)
                .offset(x: 145, y: 220)
        }
    }

    /// 对方是否在线：最近 2 分钟内有位置更新（后端 presence 事件接入前的本地判断）
    private var partnerOnline: Bool {
        guard let ts = store.lastKnownPartnerLocation?.timestamp else { return false }
        return Date().timeIntervalSince(ts) < 120
    }

    /// 未配对时的引导卡片（替代 PartnerHero）
    private var pairPromptCard: some View {
        Button {
            session.showPairSheet = true
        } label: {
            VStack(spacing: 10) {
                Text("🔗").font(.system(size: 40))
                Text("还没有和 TA 配对")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("点这里输入 TA 的配对码，\n或把你的码发给 TA")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("去配对")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Theme.primary)
                    .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .softShadow(Theme.shadowMd)
        }
        .buttonStyle(.plain)
    }

    /// 锁定 TA 的 App 使用（App 内全屏遮罩，不是系统锁屏）
    private var lockButton: some View {
        Button {
            showLockSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text("锁定 TA 的手机")
                    .font(.system(size: Theme.fontSm, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.48, green: 0.22, blue: 0.68),
                        Color(red: 0.30, green: 0.12, blue: 0.48)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .softShadow(Theme.shadowSm)
        }
        .buttonStyle(.plain)
    }

    /// 请求看 TA 的屏幕（对方需在弹窗里点同意）
    private var shotButton: some View {
        Button {
            Task { await requestShot() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                Text("看看 TA 的屏幕")
                    .font(.system(size: Theme.fontSm, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Theme.primary)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.primary.opacity(0.35), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func requestShot() async {
        guard let http = session.realtime as? HTTPRealtimeSyncService else { return }
        do {
            try await http.requestScreenshot()
            showToast("已请求，等 TA 同意", icon: "camera.viewfinder")
            Log.info("RealtimeMap", "已请求截图")
        } catch {
            showToast("请求失败：\(error.localizedDescription)", icon: "exclamationmark.triangle")
            Log.error("RealtimeMap", "截图请求失败：\(error)")
        }
    }

    /// 一键 SOS
    private var sosButton: some View {
        Button {
            Task { await sendSOS() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sos")
                Text("紧急提醒 TA")
                    .font(.system(size: Theme.fontSm, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.90, green: 0.22, blue: 0.26),
                        Color(red: 0.72, green: 0.10, blue: 0.36)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .softShadow(Theme.shadowSm)
        }
        .buttonStyle(.plain)
    }

    /// 历史轨迹入口
    private var trackButton: some View {
        Button {
            showTracks = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                Text("查看历史轨迹")
                    .font(.system(size: Theme.fontSm, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Theme.violet)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Theme.violet.opacity(0.35), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var lockSheet: some View {
        NavigationStack {
            Form {
                Section("锁定理由（TA 会看到）") {
                    TextField("比如：上课别玩游戏", text: $lockReason)
                }
                Section("锁定时长") {
                    Picker("时长", selection: $lockMinutes) {
                        Text("5 分钟").tag(5)
                        Text("15 分钟").tag(15)
                        Text("30 分钟").tag(30)
                        Text("60 分钟").tag(60)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Text("锁定后 TA 的 App 会被全屏遮罩盖住，答对数学题才能提前解锁。\n这是 App 内的使用限制，不是系统锁屏 —— iOS 不允许普通 App 锁设备。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("锁定 TA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showLockSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(locking ? "锁定中…" : "锁定") {
                        Task { await doLock() }
                    }
                    .disabled(locking)
                }
            }
        }
    }

    @MainActor
    private func sendSOS() async {
        guard let http = session.realtime as? HTTPRealtimeSyncService else { return }
        let lat = session.lastLocation?.coordinate.latitude
        let lng = session.lastLocation?.coordinate.longitude
        do {
            try await http.sendSOS(lat: lat, lng: lng)
            showToast("已发出紧急提醒", icon: "sos")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Log.warn("RealtimeMap", "已发送 SOS（含位置=\(lat != nil)）")
        } catch {
            showToast("发送失败：\(error.localizedDescription)", icon: "exclamationmark.triangle")
            Log.error("RealtimeMap", "SOS 发送失败：\(error)")
        }
    }

    @MainActor
    private func doLock() async {        guard let http = session.realtime as? HTTPRealtimeSyncService else { return }
        locking = true
        defer { locking = false }
        do {
            let reason = lockReason.trimmingCharacters(in: .whitespaces)
            try await http.lockPartner(
                reason: reason.isEmpty ? "乖乖听我的" : reason,
                minutes: lockMinutes
            )
            showLockSheet = false
            lockReason = ""
            showToast("已锁定 TA \(lockMinutes) 分钟", icon: "lock.fill")
            Log.info("RealtimeMap", "已锁定 TA \(lockMinutes) 分钟")
        } catch {
            showToast("锁定失败：\(error.localizedDescription)", icon: "exclamationmark.triangle")
            Log.error("RealtimeMap", "锁定失败：\(error)")
        }
    }

    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatusBar()
                GuardBanner(settings: session.guardSettings)
                if store.isPaired || session.isPaired {
                    PartnerHero(
                        name: store.partner?.displayName ?? "TA",
                        avatar: "👧🏻",
                        distanceKm: store.distanceKmToPartner(myLocation: session.lastLocation),
                        isOnline: partnerOnline,
                        deviceModel: store.partnerStatus?.deviceModel ?? "iOS",
                        batteryPercent: store.partnerStatus?.battery
                            ?? store.lastKnownPartnerLocation?.battery.map { Int(($0.level * 100).rounded()) },
                        networkLabel: store.partnerStatus?.network
                            ?? (partnerOnline ? "实时共享中" : "暂时离线")
                    )
                } else {
                    pairPromptCard
                }
                mapSection
                DistanceCard(
                    locationEnabled: $locationEnabled,
                    distanceMeters: distanceMeters,
                    partnerName: store.partner?.displayName ?? "TA"
                ) { newValue in
                    showToast(
                        newValue ? "已开启实时定位 · 共享位置给 TA" : "已关闭定位 · TA 将看不到你的位置",
                        icon: newValue ? "location.fill" : "moon.fill"
                    )
                }
                PokeGrid(partnerName: store.partner?.displayName ?? "TA") { item in
                    showToast("已发送给 TA：\(item.name)", icon: "paperplane.fill")
                }
                if store.isPaired || session.isPaired {
                    sosButton
                    lockButton
                    shotButton
                    trackButton
                }
                QuickCards { kind in
                    showToast("打开「\(kind.title)」", icon: kind.systemIcon)
                }
                Color.clear.frame(height: 100) // bottom nav 空间
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    /// 诊断浮层：显示当前引擎、坐标、百度 SDK 状态
    private var mapDiagnosticText: String {
        let engine = guardSettings.mapEngine == .baidu ? "百度" : "苹果"
        let coord: String
        if let c = mapCenter {
            coord = String(format: "%.4f,%.4f", c.latitude, c.longitude)
        } else {
            coord = "无坐标"
        }
        let extra: String
        if guardSettings.mapEngine == .baidu {
            extra = " ·AK:\(BaiduMapManager.shared.startSucceeded ? "ok" : "fail")"
        } else {
            extra = ""
        }
        return "\(engine) · \(coord)\(extra)"
    }

    // MARK: - 地图区: MapKit 真实地图

    /// 百度地图上的两个人
    private var baiduPeople: [BaiduMapPerson] {
        var list: [BaiduMapPerson] = []
        if let me = session.lastLocation?.coordinate {
            list.append(BaiduMapPerson(id: "me", name: "我", coordinate: me, isMe: true))
        }
        if let p = store.lastKnownPartnerLocation {
            list.append(BaiduMapPerson(
                id: "partner",
                name: store.partner?.displayName ?? "TA",
                coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon),
                isMe: false
            ))
        }
        return list
    }

    private var baiduMapType: BMKMapType {
        switch mapStyle {
        case .satellite: return .satellite
        default: return .standard
        }
    }

    /// 还没有定位时的占位（替代原来的手绘假图）
    private var locatingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .scaleEffect(1.2)
            Text("正在获取定位…")
                .font(.system(size: Theme.fontSm, weight: .medium))
                .foregroundColor(Theme.text)
            Text("首次定位在室外约 1-3 秒，室内可能更久")
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var mapSection: some View {
        VStack(spacing: 6) {
            // 诊断状态条：无论地图是否渲染出来都能看到当前状态
            HStack(spacing: 6) {
                Circle()
                    .fill(guardSettings.mapEngine == .baidu
                          ? (BaiduMapManager.shared.startSucceeded ? Theme.success : Color.orange)
                          : Theme.success)
                    .frame(width: 6, height: 6)
                Text(mapDiagnosticText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 4)

        ZStack(alignment: .topTrailing) {
            if let center = mapCenter {
                if guardSettings.mapEngine == .baidu {
                    BaiduMapView(
                        center: center,
                        zoomLevel: 15,
                        people: baiduPeople,
                        mapType: baiduMapType
                    )
                    .id("baidu-\(guardSettings.mapEngine.rawValue)")
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
                    .softShadow(Theme.shadowMd)
                } else {
                    MapKitView(
                        center: center,
                        partner: mapPartner,
                        me: mapMe,
                        style: mapStyle
                    )
                    .id("apple-\(mapStyle.rawValue)")
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
                    .softShadow(Theme.shadowMd)
                }
            } else {
                // 不再显示手绘假地图，如实告诉用户正在定位
                locatingPlaceholder
            }

            // 地图样式切换（只有真地图才显示；仿 LinkUp 的「经典/卫星」切换）
            if mapCenter != nil && guardSettings.mapEngine == .apple {
                HStack(spacing: 6) {
                    ForEach(MapKitView.MapStyleOption.allCases) { opt in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { mapStyle = opt }
                            UserDefaults.standard.set(opt.rawValue, forKey: "map.style")
                        } label: {
                            Image(systemName: opt.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(mapStyle == opt ? .white : Theme.text)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().fill(mapStyle == opt ? Theme.primary : Color.white.opacity(0.92))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(opt.label)
                    }
                }
                .padding(10)
            }
        }
        }
    }

    // MARK: - Toast

    private var toastLayer: some View {
        VStack {
            Spacer()
            if let msg = toastMessage {
                HStack(spacing: 6) {
                    if let icon = toastIcon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(msg)
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [Color(red: 0.165, green: 0.078, blue: 0.188),
                                     Color(red: 0.227, green: 0.122, blue: 0.267)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                )
                .softShadow(Theme.shadowMd)
                .padding(.bottom, 110)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    /// 地图中心点: 优先用对方位置, 没有则用我自己的位置
    private var mapCenter: CLLocationCoordinate2D? {
        // 优先用自己的位置：本地定位 1-2 秒就有，不必等对方推送
        if let me = session.lastLocation {
            return me.coordinate
        }
        // 自己还没定位时，至少把对方的位置显示出来
        if let p = store.lastKnownPartnerLocation {
            return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        }
        return nil
    }

    private var mapPartner: MapPerson? {
        guard let p = store.lastKnownPartnerLocation else { return nil }
        return MapPerson(
            id: p.userId,
            name: store.partner?.displayName ?? "TA",
            coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        )
    }

    private var mapMe: MapPerson? {
        guard let me = session.lastLocation else { return nil }
        return MapPerson(
            id: session.currentUser.id,
            name: "我",
            coordinate: me.coordinate
        )
    }

    private var distanceMeters: Int? {
        guard let km = store.distanceKmToPartner(myLocation: session.lastLocation) else {
            return store.lastKnownPartnerLocation != nil ? 1200 : nil
        }
        return Int((km * 1000).rounded())
    }

    private func showToast(_ message: String, icon: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            toastMessage = message
            toastIcon = icon
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeIn(duration: 0.25)) {
                toastMessage = nil
                toastIcon = nil
            }
        }
    }
}

// MARK: - 轨迹回放弹层

struct TrackSheet: View {
    let onClose: () -> Void
    @StateObject private var vm: TrackPlaybackViewModel

    init(realtime: RealtimeSyncServiceProtocol, onClose: @escaping () -> Void) {
        _vm = StateObject(wrappedValue: TrackPlaybackViewModel(sync: realtime))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            TrackPlaybackView(viewModel: vm)
                .navigationTitle("轨迹回放")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { onClose() }
                    }
                }
                .task { await vm.load() }
        }
    }
}

#Preview {
    RealtimeMapScreen()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
