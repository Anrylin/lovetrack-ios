import SwiftUI
import CoreLocation

/// App 主壳 — 4 tabs 切换 (守护 / 位置 / 消息 / 我的)
/// 复刻原型 love-location.html 的 bottom-nav + 内容区结构
public struct AppTabView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    @State private var selectedTab: AppTab = .location

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // 内容区
            Group {
                switch selectedTab {
                case .guard_:     GuardScreen()
                case .location:   RealtimeMapScreen()
                case .message:    MessageScreen()
                case .stats:      StatisticsScreen()
                case .profile:    ProfileScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            // 自定义底部导航
            LoveTrackBottomNav(selection: tabBinding)
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var tabBinding: Binding<LoveTrackBottomNav.Tab> {
        Binding(
            get: {
                switch selectedTab {
                case .guard_:   return .protect
                case .location: return .location
                case .message:  return .message
                case .stats:    return .stats
                case .profile:  return .profile
                }
            },
            set: { newTab in
                withAnimation(.easeInOut(duration: 0.2)) {
                    switch newTab {
                    case .protect:  selectedTab = .guard_
                    case .location: selectedTab = .location
                    case .message:  selectedTab = .message
                    case .stats:    selectedTab = .stats
                    case .profile:  selectedTab = .profile
                    }
                }
            }
        )
    }
}

public enum AppTab: String, CaseIterable, Identifiable {
    case guard_ = "guard"
    case location, message, stats, profile

    public var id: String { rawValue }
}

// MARK: - 统计页

/// 统计 Tab：今日概览 / 近 7 天活动 / 本 App 使用 / 轨迹入口
public struct StatisticsScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    @StateObject private var device = DeviceStatusMonitor()
    @StateObject private var usage = UsageStats()

    @State private var weekPoints: [(day: String, count: Int)] = []
    @State private var showTracks = false

    public init() {}

    public var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    StatusBar()
                    if store.isPaired {
                        todayCard
                        weekChart
                        usageCard
                        trackEntry
                        baiduMapCard
                    } else {
                        notPairedHint
                    }
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .task { await loadWeek() }
        .sheet(isPresented: $showTracks) {
            TrackSheet(realtime: session.realtime) { showTracks = false }
        }
    }

    // MARK: 数据

    private var maxCount: Int {
        max(1, weekPoints.map { $0.count }.max() ?? 1)
    }

    private var pairedDays: String {
        guard let rel = store.relationship else { return "—" }
        let d = (Calendar.current.dateComponents([.day], from: rel.pairedAt, to: Date()).day ?? 0) + 1
        return "\(max(1, d))"
    }

    private func shortDay(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(parts[1])/\(parts[2])"
    }

    @MainActor
    private func loadWeek() async {
        usage.refresh()
        device.refreshBattery()
        guard let http = session.realtime as? HTTPRealtimeSyncService, http.isLoggedIn else { return }
        do {
            let json = try await http.authedGet(path: "api/location/tracks")
            let tracks = (json["tracks"] as? [[String: Any]]) ?? []
            weekPoints = tracks.prefix(7).compactMap { t in
                guard let day = t["day"] as? String, let n = t["pointCount"] as? Int else { return nil }
                return (day, n)
            }
            Log.info("Statistics", "近 7 天轨迹点数：\(weekPoints.map { "\($0.day)=\($0.count)" }.joined(separator: ","))")
        } catch {
            Log.warn("Statistics", "加载统计失败：\(error.localizedDescription)")
        }
    }

    // MARK: 卡片

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
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

    private func header(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primary, Theme.violet],
                    startPoint: .leading, endPoint: .trailing
                ))
            Text(title)
                .font(.system(size: Theme.fontMd, weight: .semibold))
                .foregroundColor(Theme.text)
            Spacer()
        }
    }

    private func statBox(icon: String, value: String, unit: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primary, Theme.violet],
                    startPoint: .leading, endPoint: .trailing
                ))
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Theme.text)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var todayCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                header("今日概览", icon: "calendar")
                HStack(spacing: 10) {
                    statBox(icon: "location.fill", value: "\(usage.reportCount)", unit: "次", label: "我的上报")
                    statBox(icon: "clock.fill", value: "\(store.partnerStatus?.appMinutes ?? 0)", unit: "分", label: "TA 今日使用")
                    statBox(icon: "heart.fill", value: pairedDays, unit: "天", label: "配对天数")
                }
            }
        }
    }

    private var weekChart: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                header("近 7 天位置活动", icon: "chart.bar.fill")
                if weekPoints.isEmpty {
                    Text("还没有轨迹数据，位置共享一段时间后会出现")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textMuted)
                        .padding(.vertical, 12)
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(weekPoints, id: \.day) { item in
                            VStack(spacing: 4) {
                                Text("\(item.count)")
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.textMuted)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(LinearGradient(
                                        colors: [Theme.primary, Theme.violet],
                                        startPoint: .bottom, endPoint: .top
                                    ))
                                    .frame(height: max(4, CGFloat(item.count) / CGFloat(maxCount) * 70))
                                Text(shortDay(item.day))
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.textMuted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 108, alignment: .bottom)
                }
            }
        }
    }

    private var usageCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                header("TA 的手机", icon: "iphone")
                HStack(spacing: 10) {
                    statBox(icon: "clock.fill", value: "\(store.partnerStatus?.appMinutes ?? 0)", unit: "分", label: "今日使用")
                    statBox(icon: "arrow.up.app", value: "\(store.partnerStatus?.appLaunches ?? 0)", unit: "次", label: "启动")
                    statBox(icon: "battery.75", value: partnerBatteryText, unit: "", label: "电量")
                }
                HStack(spacing: 10) {
                    statBox(icon: "wifi", value: store.partnerStatus?.network ?? "—", unit: "", label: "网络")
                    statBox(
                        icon: "internaldrive",
                        value: store.partnerStatus?.storageFreeMB.map { String(format: "%.1fG", Double($0) / 1024) } ?? "—",
                        unit: "",
                        label: "可用空间"
                    )
                    statBox(icon: "bolt.slash", value: store.partnerStatus?.lowPower == true ? "开" : "关", unit: "", label: "低电量")
                }
                Text("以上是 TA 的 App 主动上报的真实状态（每 60 秒一次）。iOS 不允许读取其他 App 的使用时长，这里的「使用」指 TA 打开本 App 的时长。")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    private var partnerBatteryText: String {
        guard let b = store.partnerStatus?.battery else { return "—" }
        return "\(b)%"
    }

    private var trackEntry: some View {
        Button {
            showTracks = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.primary, Theme.violet],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("查看历史轨迹")
                    .font(.system(size: Theme.fontSm, weight: .medium))
                    .foregroundColor(Theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSubtle)
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
        .buttonStyle(.plain)
    }

    // MARK: 百度地图验证区块

    private var baiduCenter: CLLocationCoordinate2D {
        if let p = store.lastKnownPartnerLocation {
            return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        }
        if let me = session.lastLocation?.coordinate {
            return me
        }
        return CLLocationCoordinate2D(latitude: 39.915, longitude: 116.404)
    }

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

    private var baiduMapCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                header("地图引擎（百度）", icon: "map.fill")
                BaiduMapView(center: baiduCenter, zoomLevel: 15, people: baiduPeople)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
                Text("这是百度地图实测区块。能正常出图说明 AK 通过、底图可加载，下一步就用它替换主页地图。")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    private var notPairedHint: some View {
        VStack(spacing: 10) {
            Text("💞").font(.system(size: 40))
            Text("配对后才有统计数据")
                .font(.system(size: Theme.fontSm, weight: .medium))
                .foregroundColor(Theme.text)
            Button {
                session.showPairSheet = true
            } label: {
                Text("去配对")
                    .font(.system(size: Theme.fontXs, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.primary))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

#Preview {
    AppTabView()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
