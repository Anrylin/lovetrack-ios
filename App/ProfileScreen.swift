import SwiftUI
import Foundation
import Network
import UIKit
import CoreLocation

/// 我的 Tab — 个人资料 hero + 守护数据 + 设置 + 会员入口
public struct ProfileScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore
    @EnvironmentObject var guardSettings: GuardSettings

    @ObservedObject private var device = DeviceStatusMonitor.shared
    @StateObject private var usage = UsageStats()

    @State private var showEdit = false
    @State private var editNickname = ""
    @State private var editEmoji = "🐰"
    @State private var saving = false
    @State private var editError: String?

    /// 与后端 EMOJIS 白名单保持一致，否则会被后端回退成默认值
    private let emojis = ["🐱", "🐶", "🦊", "🐰", "🐻", "🐼", "🐨", "🐯", "🦁", "🐸", "🐧", "🐳"]

    public init() {}

    public var body: some View {
        ZStack {
            backgroundGradient
            contentScroll
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showEdit) { editSheet }
        .onAppear {
            device.refreshBattery()
            device.refreshStorage()
            usage.refresh()
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        ZStack {
            Theme.bg
            LinearGradient(
                colors: [Color(red: 1.00, green: 0.84, blue: 0.91).opacity(0.5),
                         Color.clear,
                         Color(red: 0.91, green: 0.84, blue: 1.00).opacity(0.5)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 14) {
                StatusBar()
                profileHero
                deviceStatusCard
                usageCard
                vipCard
                settingsGroup
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Profile hero

    private var profileHero: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.3)).frame(width: 160, height: 160)
                .blur(radius: 2).offset(x: 130, y: -50)
            Circle().fill(Color.white.opacity(0.18)).frame(width: 120, height: 120)
                .blur(radius: 2).offset(x: -120, y: 60)

            VStack(spacing: 12) {
                HStack(alignment: .center) {
                    Spacer()
                    Button {} label: {
                        Image(systemName: "qrcode")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.25)))
                    }
                    Button {
                        showEdit = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.25)))
                    }
                }
                .padding(.top, 4)

                ZStack {
                    Circle().fill(Color.white.opacity(0.5))
                        .frame(width: 84, height: 84)
                    Circle().fill(LinearGradient(colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.91),
                        Color(red: 0.91, green: 0.84, blue: 1.00)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 76, height: 76)
                    .overlay(Text(session.myEmoji).font(.system(size: 38)))
                }

                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(session.currentUser.displayName)
                            .font(.system(size: Theme.fontXl, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                    }
                    Text(session.myAccount.isEmpty ? "ID: \(String(session.currentUser.id.prefix(8)))" : "@\(session.myAccount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }

                HStack(spacing: 16) {
                    if store.isPaired, let rel = store.relationship {
                        relationshipPill(systemIcon: "heart.fill", text: "在一起 \(daysTogether(rel)) 天")
                    } else {
                        relationshipPill(systemIcon: "heart.slash", text: "暂未配对")
                    }
                    relationshipPill(
                        systemIcon: "shield.lefthalf.filled",
                        text: session.isPaired ? "守护中" : "待开启"
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(Theme.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
        .softShadow(Theme.shadowMd)
    }

    private func relationshipPill(systemIcon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemIcon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.25)))
    }

    // MARK: - 手机状态 / 使用报告

    private var pairDaysText: String {
        guard store.isPaired, let rel = store.relationship else { return "—" }
        return "\(daysTogether(rel))"
    }

    private func cardShell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1.5)
            )
            .softShadow(Theme.shadowSm)
    }

    private var deviceStatusCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "iphone")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    Text("手机状态")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text("本机实时")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSubtle)
                }
                HStack(spacing: 10) {
                    statItem(
                        systemIcon: device.charging ? "battery.100.bolt" : "battery.75",
                        value: device.battery >= 0 ? "\(device.battery)%" : "—",
                        label: device.charging ? "充电中" : "电量"
                    )
                    statItem(systemIcon: "wifi", value: device.network, label: "网络")
                    statItem(
                        systemIcon: "internaldrive",
                        value: device.storageTotalGB > 0
                            ? String(format: "%.1fG", device.storageFreeGB)
                            : "—",
                        label: "可用空间"
                    )
                    statItem(
                        systemIcon: "bolt.slash",
                        value: device.lowPower ? "开启" : "关闭",
                        label: "低电量"
                    )
                }
            }
        }
    }

    private var usageCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.violet)
                    Text("今日使用")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text("仅统计本 App")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSubtle)
                }
                HStack(spacing: 10) {
                    statItem(systemIcon: "clock.fill", value: "\(usage.todayMinutes)", label: "分钟")
                    statItem(systemIcon: "arrow.up.app", value: "\(usage.launchCount)", label: "启动")
                    statItem(systemIcon: "location.fill", value: "\(usage.reportCount)", label: "位置上报")
                    statItem(systemIcon: "heart.fill", value: pairDaysText, label: "配对天数")
                }
            }
        }
    }

    // MARK: - Stats row（旧版假数据，已由上面两张卡取代）

    private var statsRow: some View {
        HStack(spacing: 10) {
            statItem(systemIcon: "mappin.and.ellipse", value: "1,234", label: "位置更新")
            statItem(systemIcon: "envelope.fill", value: "567", label: "发送戳一戳")
            statItem(systemIcon: "shield.fill", value: "42", label: "守护天数")
            statItem(systemIcon: "gift.fill", value: "18", label: "纪念日")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    private func statItem(systemIcon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primary, Theme.violet],
                    startPoint: .leading, endPoint: .trailing
                ))
            Text(value)
                .font(.system(size: Theme.fontMd, weight: .bold))
                .foregroundColor(Theme.text)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - VIP

    private var vipCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 1.00, green: 0.84, blue: 0.66),
                                                  Color(red: 0.95, green: 0.59, blue: 0.27)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Image(systemName: "crown.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("开通 VIP 守护")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("PRO")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                         startPoint: .leading, endPoint: .trailing))
                        )
                        .foregroundColor(.white)
                }
                Text("解锁 30 天轨迹回放、无限守护、家人地图")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSubtle)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.00, green: 0.97, blue: 0.88),
                                              Color(red: 1.00, green: 0.92, blue: 0.96)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Color(red: 0.95, green: 0.78, blue: 0.50).opacity(0.4), lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    // MARK: - Settings group

    private var lowBatterySubtitle: String {
        guardSettings.notifyOnLowBattery
            ? "低电提醒已开启 · 对方 < 20% 时提示"
            : "低电提醒已关闭"
    }

    private var privacySubtitle: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: return "定位：始终允许"
        case .authorizedWhenInUse: return "定位：使用 App 期间"
        case .denied: return "定位：已拒绝，请去系统设置开启"
        case .restricted: return "定位：受限"
        case .notDetermined: return "定位：尚未授权"
        @unknown default: return "定位：未知"
        }
    }

    private var appVersionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (\(b))"
    }

    private var settingsGroup: some View {
        VStack(spacing: 0) {
            settingsRow(systemIcon: "bell.fill", title: "通知提醒", subtitle: lowBatterySubtitle,
                       color: Theme.primarySoft, tint: Theme.primary)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "lock.fill", title: "隐私与权限", subtitle: privacySubtitle,
                       color: Color(red: 0.92, green: 0.99, blue: 0.96), tint: Theme.success)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "info.circle.fill", title: "关于 LoveTrack", subtitle: appVersionText,
                       color: Theme.surface2, tint: Theme.textMuted)
        }
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    private func settingsRow(systemIcon: String, title: String, subtitle: String,
                             color: Color, tint: Color) -> some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                        .fill(color)
                        .frame(width: 32, height: 32)
                    Image(systemName: systemIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: Theme.fontSm, weight: .medium))
                        .foregroundColor(Theme.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSubtle)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 编辑资料

    /// 在一起第几天（配对当天算第 1 天）
    private func daysTogether(_ rel: Relationship) -> Int {
        let d = Calendar.current.dateComponents([.day], from: rel.pairedAt, to: Date()).day ?? 0
        return max(1, d + 1)
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("昵称（TA 看到的名字）") {
                    TextField("昵称", text: $editNickname)
                }
                Section("头像") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(emojis, id: \.self) { e in
                            Button {
                                editEmoji = e
                            } label: {
                                Text(e)
                                    .font(.system(size: 26))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(editEmoji == e ? Color.purple.opacity(0.18) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let err = editError {
                    Section {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button("退出登录", role: .destructive) {
                        showEdit = false
                        session.signOutAccount()
                    }
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showEdit = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "保存中…" : "保存") {
                        Task { await saveProfile() }
                    }
                    .disabled(saving || editNickname.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                editNickname = session.currentUser.displayName
                editEmoji = session.myEmoji
                editError = nil
            }
        }
    }

    @MainActor
    private func saveProfile() async {
        let trimmed = editNickname.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            editError = "昵称不能为空"
            return
        }
        guard let http = session.realtime as? HTTPRealtimeSyncService else {
            editError = "网络层未初始化"
            return
        }

        saving = true
        editError = nil
        defer { saving = false }

        do {
            try await http.updateMyProfile(nickname: trimmed, emoji: editEmoji)
            session.currentUser = User(id: session.currentUser.id, displayName: trimmed)
            session.myEmoji = editEmoji
            showEdit = false
            Log.info("ProfileScreen", "资料已保存：\(trimmed) \(editEmoji)")
        } catch {
            editError = friendly(error)
            Log.error("ProfileScreen", "保存失败：\(error)")
        }
    }

    private func friendly(_ error: Error) -> String {
        if let e = error as? HTTPRealtimeSyncService.ServiceError {
            switch e {
            case let .httpStatus(code, body):
                switch code {
                case 400: return "昵称或头像不合法（昵称最多 20 字）"
                case 401: return "登录已失效，请重新登录"
                case 0: return "连不上服务器"
                default: return "服务器返回 \(code)\(body.isEmpty ? "" : "：\(body.prefix(50))")"
                }
            case .decoding: return "服务器返回格式异常"
            case .connectionClosed: return "连接已断开"
            }
        }
        if let u = error as? URLError {
            return "网络错误：\(u.localizedDescription)"
        }
        return error.localizedDescription
    }
}

// MARK: - 手机状态采集（本机）

/// 采集电量、充电、低电量模式、网络、存储 —— 全部是系统真实值。
/// 对方的手机状态需要上报后端再由服务端推送，这里只负责本机。
final class DeviceStatusMonitor: ObservableObject {
    /// 全局共享实例（AppSession 上报状态时也要读）
    static let shared = DeviceStatusMonitor()

    @Published var battery: Int = -1        // -1 表示系统未提供（模拟器常见）
    @Published var charging = false
    @Published var lowPower = false
    @Published var network = "未知"
    @Published var storageFreeGB: Double = 0
    @Published var storageTotalGB: Double = 0

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "lovetrack.device.status")
    private var timer: Timer?

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        refreshStorage()
        startNetworkMonitor()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refreshBattery()
            self?.refreshStorage()
        }
    }

    deinit {
        monitor.cancel()
        timer?.invalidate()
    }

    func refreshBattery() {
        let level = UIDevice.current.batteryLevel
        let pct = level < 0 ? -1 : Int((level * 100).rounded())
        let state = UIDevice.current.batteryState
        let isCharging = (state == .charging || state == .full)
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        DispatchQueue.main.async { [weak self] in
            self?.battery = pct
            self?.charging = isCharging
            self?.lowPower = low
        }
    }

    func refreshStorage() {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? NSNumber,
              let total = attrs[.systemSize] as? NSNumber else { return }
        let freeGB = Double(free.int64Value) / 1_073_741_824.0
        let totalGB = Double(total.int64Value) / 1_073_741_824.0
        DispatchQueue.main.async { [weak self] in
            self?.storageFreeGB = freeGB
            self?.storageTotalGB = totalGB
        }
    }

    private func startNetworkMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            let label: String
            if path.status != .satisfied {
                label = "离线"
            } else if path.usesInterfaceType(.wifi) {
                label = "Wi-Fi"
            } else if path.usesInterfaceType(.cellular) {
                label = "蜂窝"
            } else if path.usesInterfaceType(.wiredEthernet) {
                label = "有线"
            } else {
                label = "其他"
            }
            DispatchQueue.main.async { self?.network = label }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - App 使用统计

/// 只能统计 App 自身：今日前台时长、启动次数、位置上报次数。
/// iOS 的系统级「屏幕使用时间 / App 使用排行」需要 Apple 特批的
/// com.apple.developer.family-controls 权限，个人签名版本拿不到。
final class UsageStats: ObservableObject {
    @Published var todayMinutes = 0
    @Published var launchCount = 0
    @Published var reportCount = 0

    private enum Key {
        static let day = "usage.day"
        static let minutes = "usage.minutes"
        static let launches = "usage.launches"
        static let reports = "usage.reports"
    }

    private var tickStart = Date()
    private var timer: Timer?

    init() {
        rolloverIfNewDay()
        let d = UserDefaults.standard
        d.set(d.integer(forKey: Key.launches) + 1, forKey: Key.launches)
        launchCount = d.integer(forKey: Key.launches)
        reportCount = d.integer(forKey: Key.reports)
        todayMinutes = d.integer(forKey: Key.minutes)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.flushMinutes()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// 每分钟把已过去的整分钟累加进今日总量
    func flushMinutes() {
        let mins = Int(Date().timeIntervalSince(tickStart) / 60)
        guard mins > 0 else { return }
        tickStart = Date()
        let d = UserDefaults.standard
        let total = d.integer(forKey: Key.minutes) + mins
        d.set(total, forKey: Key.minutes)
        DispatchQueue.main.async { [weak self] in self?.todayMinutes = total }
    }

    /// 位置上报一次就 +1（供 AppSession 调用）
    static func countReport() {
        let d = UserDefaults.standard
        d.set(d.integer(forKey: Key.reports) + 1, forKey: Key.reports)
    }

    /// 切回前台时刷新（同时处理跨天重置）
    func refresh() {
        rolloverIfNewDay()
        let d = UserDefaults.standard
        todayMinutes = d.integer(forKey: Key.minutes)
        launchCount = d.integer(forKey: Key.launches)
        reportCount = d.integer(forKey: Key.reports)
    }

    private func rolloverIfNewDay() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        let d = UserDefaults.standard
        if d.string(forKey: Key.day) != today {
            d.set(today, forKey: Key.day)
            d.set(0, forKey: Key.minutes)
            d.set(0, forKey: Key.launches)
            d.set(0, forKey: Key.reports)
        }
    }
}

#Preview {
    ProfileScreen()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
