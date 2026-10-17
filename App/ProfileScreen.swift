import SwiftUI
import Foundation

/// 我的 Tab — 个人资料 hero + 守护数据 + 设置 + 会员入口
public struct ProfileScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

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
                statsRow
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

    // MARK: - Stats row

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

    private var settingsGroup: some View {
        VStack(spacing: 0) {
            settingsRow(systemIcon: "shield.fill", title: "守护设置", subtitle: "位置、低电、安全区",
                       color: Theme.violetSoft, tint: Theme.violet)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "bell.fill", title: "通知提醒", subtitle: "消息、戳一戳、电量",
                       color: Theme.primarySoft, tint: Theme.primary)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "lock.fill", title: "隐私与权限", subtitle: "位置、通讯录、轨迹",
                       color: Color(red: 0.92, green: 0.99, blue: 0.96), tint: Theme.success)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "paintbrush.fill", title: "主题外观", subtitle: "粉紫 / 星空 / 森系",
                       color: Color(red: 0.95, green: 0.91, blue: 1.00), tint: Color(red: 0.55, green: 0.36, blue: 0.96))
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "heart.fill", title: "邀请好友", subtitle: "双方各得 7 天 VIP",
                       color: Color(red: 1.00, green: 0.94, blue: 0.88), tint: Color(red: 0.95, green: 0.59, blue: 0.27))
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "questionmark.circle.fill", title: "帮助与反馈", subtitle: "常见问题、联系客服",
                       color: Theme.surface2, tint: Theme.textMuted)
            Divider().padding(.leading, 50)
            settingsRow(systemIcon: "info.circle.fill", title: "关于爱合", subtitle: "v0.1.0 · 用科技守护亲密",
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

#Preview {
    ProfileScreen()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
