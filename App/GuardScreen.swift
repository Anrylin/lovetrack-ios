import SwiftUI
import UIKit

/// 守护 Tab — 大守护状态 hero + 今日守护数据 + 设置项
public struct GuardScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore
    @EnvironmentObject var guardSettings: GuardSettings

    /// 守护总开关：直接联动已保存的档位（off ↔ standard），不再是本地假开关
    private var guardEnabled: Bool {
        guardSettings.mode != .off
    }

    @State private var showEmergency = false

    public init() {}

    public var body: some View {
        ZStack {
            backgroundGradient
            contentScroll
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showEmergency) {
            NavigationStack {
                EmergencyContactsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showEmergency = false }
                        }
                    }
            }
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
                if store.isPaired {
                    guardHero
                    todayStats
                    guardianTimeline
                } else {
                    notPairedHint
                }
                settingsSection
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 未配对提示（避免未配对时显示任何虚假守护数据）

    private var notPairedHint: some View {
        VStack(spacing: 12) {
            Text("💞").font(.system(size: 44))
            Text("还没有和 TA 配对")
                .font(.system(size: Theme.fontLg, weight: .semibold))
                .foregroundColor(Theme.text)
            Text("配对后才能开启守护、查看 TA 的位置和电量")
                .font(.system(size: Theme.fontXs))
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textMuted)
            Button {
                session.showPairSheet = true
            } label: {
                Text("去配对")
                    .font(.system(size: Theme.fontSm, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.primary))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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

    // MARK: - 真实数据

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    private var partnerDisplayName: String {
        store.partner?.displayName ?? "TA"
    }

    /// 对方的头像（后端暂无 emoji 字段，用 TA 占位）
    private var partnerAvatarText: String {
        "TA"
    }

    private var partnerOnlineNow: Bool {
        guard let ts = store.lastKnownPartnerLocation?.timestamp else { return false }
        return Date().timeIntervalSince(ts) < 120
    }

    /// 守护时长用配对天数表示（可真实计算）
    private var guardDurationText: String {
        guard let rel = store.relationship else { return "守护已开启" }
        let days = max(1, (Calendar.current.dateComponents([.day], from: rel.pairedAt, to: Date()).day ?? 0) + 1)
        return "已守护 \(days) 天"
    }

    private var pairedDays: String {
        guard let rel = store.relationship else { return "—" }
        let d = (Calendar.current.dateComponents([.day], from: rel.pairedAt, to: Date()).day ?? 0) + 1
        return "\(max(1, d))"
    }

    private var todayReportCount: String {
        "\(UserDefaults.standard.integer(forKey: "usage.reports"))"
    }

    private var myBatteryText: String {
        let lvl = UIDevice.current.batteryLevel
        return lvl < 0 ? "—" : "\(Int((lvl * 100).rounded()))%"
    }

    // MARK: - Hero

    private var guardHero: some View {
        ZStack {
            // 装饰光斑
            Circle().fill(Color.white.opacity(0.3)).frame(width: 140, height: 140)
                .blur(radius: 2).offset(x: 130, y: -50)
            Circle().fill(Color.white.opacity(0.18)).frame(width: 100, height: 100)
                .blur(radius: 2).offset(x: -100, y: 60)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guardEnabled ? "正在守护" : "守护已关闭")
                            .font(.system(size: Theme.fontXl, weight: .bold))
                            .foregroundColor(.white)
                        Text(guardEnabled
                             ? guardDurationText
                             : "开启后实时共享位置给 TA")
                            .font(.system(size: Theme.fontXs))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    Spacer()
                    BrandToggle(isOn: Binding(
                        get: { guardSettings.mode != .off },
                        set: { newValue in
                            if newValue {
                                if guardSettings.mode == .off { guardSettings.mode = .standard }
                            } else {
                                guardSettings.mode = .off
                            }
                            session.applyGuardMode()
                            Log.info("GuardScreen", "守护总开关 → \(newValue ? "开启" : "关闭")")
                        }
                    ))
                }

                // 守护双方头像 + 中间爱心连线
                HStack(spacing: 0) {
                    guardAvatar(avatarText: partnerAvatarText, name: partnerDisplayName, isOnline: partnerOnlineNow)
                    connectorLine
                    guardAvatar(avatarText: session.myEmoji, name: session.currentUser.displayName, isOnline: true)
                }
            }
            .padding(20)
        }
        .background(Theme.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius2xl, style: .continuous))
        .softShadow(Theme.shadowMd)
    }

    private func guardAvatar(avatarText: String, name: String, isOnline: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 56, height: 56)
                Circle()
                    .fill(LinearGradient(colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.91),
                        Color(red: 0.91, green: 0.84, blue: 1.00)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(avatarText)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    )
                if isOnline {
                    Circle()
                        .fill(Color(red: 0.29, green: 0.87, blue: 0.50))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 18, y: 18)
                }
            }
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
        }
    }

    private var connectorLine: some View {
        ZStack {
            // 虚线
            Path { p in
                p.move(to: CGPoint(x: 0, y: 28))
                p.addLine(to: CGPoint(x: 80, y: 28))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .foregroundColor(.white.opacity(0.7))
            // 中间爱心
            ZStack {
                Circle().fill(Color.white.opacity(0.95))
                    .frame(width: 32, height: 32)
                Image(systemName: "heart.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .offset(x: 40, y: 28)
        }
        .frame(width: 80, height: 56)
    }

    // MARK: - 今日统计

    private var todayStats: some View {
        HStack(spacing: 10) {
            statCard(systemIcon: "mappin.circle.fill", value: todayReportCount, unit: "次", label: "今日位置更新")
            statCard(systemIcon: "heart.fill", value: pairedDays, unit: "天", label: "配对天数")
            statCard(systemIcon: "battery.75", value: myBatteryText, unit: "", label: "我的电量")
        }
    }

    private func statCard(systemIcon: String, value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LinearGradient(
                    colors: [Theme.primary, Theme.violet],
                    startPoint: .leading, endPoint: .trailing
                ))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: Theme.fontLg, weight: .bold))
                    .foregroundStyle(LinearGradient(
                        colors: [Theme.primary, Theme.violet],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text(unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
        .softShadow(Theme.shadowXs)
    }

    // MARK: - 守护时间线

    private var guardianTimeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary, Theme.violet],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    Text("今日守护时间线")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                }
                Spacer()
                Text(Self.dayFormatter.string(from: Date()))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }

            VStack(spacing: 0) {
                if let ts = store.lastKnownPartnerLocation?.timestamp {
                    timelineRow(
                        time: Self.clockFormatter.string(from: ts),
                        systemIcon: "location.fill",
                        title: "收到 TA 的位置",
                        subtitle: "\(partnerDisplayName) 最近一次同步",
                        accent: true
                    )
                    Divider().padding(.leading, 50)
                }
                if let rel = store.relationship {
                    timelineRow(
                        time: Self.clockFormatter.string(from: rel.pairedAt),
                        systemIcon: "heart.fill",
                        title: "开始守护",
                        subtitle: "与 \(partnerDisplayName) 建立配对",
                        accent: store.lastKnownPartnerLocation == nil
                    )
                    Divider().padding(.leading, 50)
                }
                if let ts = session.lastLocation?.timestamp {
                    timelineRow(
                        time: Self.clockFormatter.string(from: ts),
                        systemIcon: "location.circle.fill",
                        title: "我的位置已同步",
                        subtitle: "正在共享给 TA",
                        accent: false
                    )
                }
                if store.lastKnownPartnerLocation == nil && session.lastLocation == nil {
                    Text("暂无位置记录，等定位生效后会自动出现")
                        .font(.system(size: Theme.fontXs))
                        .multilineTextAlignment(.center)
                        .foregroundColor(Theme.textMuted)
                        .padding(.vertical, 18)
                }
            }
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

    private func timelineRow(time: String, systemIcon: String, title: String, subtitle: String, accent: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accent ? Theme.primary : Theme.textMuted)
                    .monospacedDigit()
            }
            .frame(width: 38)

            ZStack {
                Circle()
                    .fill(accent
                          ? AnyShapeStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Theme.primarySoft))
                    .frame(width: 28, height: 28)
                Image(systemName: systemIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent ? .white : Theme.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.fontSm, weight: accent ? .semibold : .medium))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - 设置项

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary, Theme.violet],
                            startPoint: .leading, endPoint: .trailing
                        ))
                    Text("守护设置")
                        .font(.system(size: Theme.fontMd, weight: .semibold))
                }
                Spacer()
            }

            VStack(spacing: 0) {
                settingRow(systemIcon: "leaf.fill", title: "省电模式", subtitle: "只在打开 App 时共享位置，进后台就停",
                          color: Color(red: 0.92, green: 0.99, blue: 0.96), tint: Theme.success,
                          isOn: $guardSettings.powerSaving)
                Divider().padding(.leading, 50)
                settingRow(systemIcon: "battery.25", title: "低电提醒", subtitle: "TA 电量 < 20% 时提醒你",
                          color: Theme.primarySoft, tint: Theme.primary,
                          isOn: $guardSettings.notifyOnLowBattery)
                Divider().padding(.leading, 50)
                Button {
                    showEmergency = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                                .fill(Color(red: 1.00, green: 0.95, blue: 0.95))
                                .frame(width: 32, height: 32)
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(red: 0.94, green: 0.27, blue: 0.27))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("紧急联系人")
                                .font(.system(size: Theme.fontSm, weight: .medium))
                            Text("一键通知 3 位紧急联系人")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textSubtle)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 50)
                NavigationLink {
                    DevLogScreen()
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                                .fill(Color(red: 0.91, green: 0.95, blue: 1.00))
                                .frame(width: 32, height: 32)
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.violet)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开发者日志")
                                .font(.system(size: Theme.fontSm, weight: .medium))
                            Text("查看 / 导出运行日志（debug 用）")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.textSubtle)
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
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

    private func settingRow(systemIcon: String, title: String, subtitle: String,
                            color: Color, tint: Color, isOn: Binding<Bool>) -> some View {
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
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            BrandToggle(isOn: isOn)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - 紧急联系人

public struct EmergencyContactsView: View {
    @State private var contacts: [(String, String, String)] = []

    private static let storeKey = "guard.emergencyContacts"

    /// 从本地读取（原来这里是硬编码的三个假联系人）
    private static func loadFromDisk() -> [(String, String, String)] {
        guard let raw = UserDefaults.standard.array(forKey: storeKey) as? [[String]] else { return [] }
        return raw.compactMap { arr in
            guard arr.count >= 2 else { return nil }
            return (arr[0], arr[1], arr.count > 2 ? arr[2] : String(arr[0].prefix(1)))
        }
    }

    private func persist() {
        UserDefaults.standard.set(contacts.map { [$0.0, $0.1, $0.2] }, forKey: Self.storeKey)
    }
    @State private var showAdd = false
    @State private var newName = ""
    @State private var newPhone = ""

    public init() {}

    public var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    if contacts.isEmpty {
                        VStack(spacing: 8) {
                            Text("👨‍👩‍👧").font(.system(size: 40))
                            Text("还没有紧急联系人")
                                .font(.system(size: Theme.fontSm, weight: .medium))
                                .foregroundColor(Theme.text)
                            Text("添加后，一键通知就能同时告知他们")
                                .font(.system(size: Theme.fontXs))
                                .multilineTextAlignment(.center)
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    }
                    ForEach(contacts.indices, id: \.self) { i in
                        contactRow(name: contacts[i].0, phone: contacts[i].1, avatarText: contacts[i].2)
                    }
                    addButton
                }
                .padding(16)
            }
        }
        .navigationTitle("紧急联系人")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { contacts = Self.loadFromDisk() }
        .alert("添加紧急联系人", isPresented: $showAdd) {
            TextField("姓名", text: $newName)
            TextField("手机号", text: $newPhone)
                .keyboardType(.phonePad)
            Button("取消", role: .cancel) {
                newName = ""
                newPhone = ""
            }
            Button("添加") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                let p = newPhone.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty && !p.isEmpty {
                    contacts.append((n, p, String(n.prefix(1))))
                    persist()
                }
                newName = ""
                newPhone = ""
            }
        }
    }

    private func contactRow(name: String, phone: String, avatarText: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.primarySoft, Theme.violetSoft],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Text(avatarText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                    startPoint: .leading, endPoint: .trailing))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: Theme.fontMd, weight: .semibold))
                Text(phone)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textMuted)
            }
            Spacer()
            Button {
                // TODO: call action
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1.5)
        )
    }

    private var addButton: some View {
        Button {
            showAdd = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("添加紧急联系人")
            }
            .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                            startPoint: .leading, endPoint: .trailing))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXl, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            )
        }
    }
}

#Preview {
    NavigationStack {
        GuardScreen()
    }
    .environmentObject(AppSession())
    .environmentObject(RelationshipStore(
        me: User(id: "u1", displayName: "我"),
        realtime: HTTPRealtimeSyncService(userId: "u1")
    ))
}
