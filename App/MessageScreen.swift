import SwiftUI

/// 消息 Tab — 互动消息列表 + 快捷发送栏
public struct MessageScreen: View {
    @EnvironmentObject var session: AppSession

    @State private var draftText: String = ""
    @State private var messages: [ChatMessage] = []
    @State private var sending = false

    public init() {}

    public var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                header
                messageList
                quickEmojiBar
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task {
            await loadMessages()
            // 5 秒轮询（WebSocket 的 msg 实时推送后续接入）
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await loadMessages()
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

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            StatusBar()
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [
                        Color(red: 1.00, green: 0.84, blue: 0.91),
                        Color(red: 0.91, green: 0.84, blue: 1.00)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                    Text("月")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("小月亮")
                        .font(.system(size: Theme.fontLg, weight: .bold))
                        .foregroundColor(Theme.text)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 6, height: 6)
                        Text("在线 · 最后位置 1 分钟前")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textMuted)
                    }
                }
                Spacer()
                quickActionButton(icon: "phone.fill", color: Theme.violetSoft, tint: Theme.violet)
                quickActionButton(icon: "video.fill", color: Theme.primarySoft, tint: Theme.primary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func quickActionButton(icon: String, color: Color, tint: Color) -> some View {
        Button(action: {}) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(color)
                )
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollView {
            VStack(spacing: 8) {
                dateDivider("今天 11月22日")
                ForEach(messages) { msg in
                    messageRow(msg)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func dateDivider(_ text: String) -> some View {
        HStack {
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, 8)
            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func messageRow(_ msg: ChatMessage) -> some View {
        switch msg.kind {
        case .system:
            HStack {
                Spacer()
                Text(msg.content)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.white.opacity(0.6))
                    )
                Spacer()
            }
        case .mine:
            HStack {
                Spacer()
                bubble(text: msg.content, isMine: true)
            }
        case .theirs(let avatar):
            HStack(alignment: .bottom, spacing: 8) {
                avatarView(avatar)
                bubble(text: msg.content, isMine: false)
                Spacer()
            }
        case .location(let systemIcon, let title, let subtitle):
            HStack(alignment: .bottom, spacing: 8) {
                avatarView("月")
                locationCard(systemIcon: systemIcon, title: title, subtitle: subtitle)
                Spacer()
            }
        case .anniversary(let days, let name):
            HStack {
                Spacer()
                anniversaryCard(days: days, name: name)
                Spacer()
            }
        }
    }

    private func avatarView(_ avatarText: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [
                    Color(red: 1.00, green: 0.84, blue: 0.91),
                    Color(red: 0.91, green: 0.84, blue: 1.00)
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 32, height: 32)
            Text(avatarText)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func bubble(text: String, isMine: Bool) -> some View {
        Text(text)
            .font(.system(size: Theme.fontSm))
            .foregroundColor(isMine ? .white : Theme.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isMine {
                        LinearGradient(
                            colors: [Theme.primary, Color(red: 0.69, green: 0.48, blue: 1.00)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    } else {
                        Color.white
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isMine ? Color.clear : Theme.border, lineWidth: 1)
            )
            .softShadow(Theme.shadowXs)
    }

    private func locationCard(systemIcon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.violet)
                Text("实时位置")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.violet)
            }
            Text(title)
                .font(.system(size: Theme.fontSm, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.violetSoft, lineWidth: 1.5)
        )
        .softShadow(Theme.shadowXs)
    }

    private func anniversaryCard(days: Int, name: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.primary, Theme.violet],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text("在一起")
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(days)")
                    .font(.system(size: Theme.font2xl, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("天")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.textMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.primary.opacity(0.2), lineWidth: 1.5)
        )
        .softShadow(Theme.shadowSm)
    }

    // MARK: - Quick emoji bar

    private var quickEmojiBar: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 10))
                    Text("常用表情")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Theme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                ForEach(["hand.wave.fill", "heart.fill", "fork.knife", "cup.and.saucer.fill",
                         "leaf.fill", "face.smiling.fill", "gift.fill", "star.fill"],
                        id: \.self) { icon in
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [Theme.primary, Theme.violet],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.surface2, Theme.violetSoft],
                                                     startPoint: .top, endPoint: .bottom))
                        )
                }
            }
            .padding(.horizontal, 16)

            HStack(spacing: 10) {
                Button {} label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                HStack(spacing: 6) {
                    TextField("说点什么…", text: $draftText)
                        .font(.system(size: Theme.fontSm))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.violet)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(LinearGradient(colors: [Theme.primary, Theme.violet],
                                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(Color.white.opacity(0.5))
            }
        )
        .overlay(
            Rectangle()
                .fill(Theme.border)
                .frame(height: 0.5),
            alignment: .top
        )
    }

    // MARK: - 真实消息（LoveLink /api/messages）

    @MainActor
    private func loadMessages() async {
        guard let http = session.realtime as? HTTPRealtimeSyncService else { return }
        do {
            let json = try await http.authedGet(path: "api/messages?limit=80")
            let list = (json["messages"] as? [[String: Any]]) ?? []
            let myId = session.currentUser.id
            var mapped: [ChatMessage] = []
            mapped.reserveCapacity(list.count)

            for m in list {
                let id = m["id"] as? String ?? UUID().uuidString
                let content = m["content"] as? String ?? ""
                let kind = m["kind"] as? String ?? "text"
                let from = m["from"] as? String ?? ""
                let at = m["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
                let timeText = Self.timeFormatter.string(from: Date(timeIntervalSince1970: at / 1000))
                let mine = (from == myId)

                switch kind {
                case "system":
                    mapped.append(.init(time: timeText, kind: .system, content: content, id: id))
                case "poke":
                    mapped.append(.init(time: timeText,
                                        kind: mine ? .mine : .theirs(avatar: "👧🏻"),
                                        content: "戳一戳",
                                        id: id))
                default:
                    mapped.append(.init(time: timeText,
                                        kind: mine ? .mine : .theirs(avatar: "👧🏻"),
                                        content: content,
                                        id: id))
                }
            }
            messages = mapped
        } catch {
            Log.warn("MessageScreen", "加载消息失败：\(error.localizedDescription)")
        }
    }

    @MainActor
    private func send() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let http = session.realtime as? HTTPRealtimeSyncService else { return }

        sending = true
        defer { sending = false }

        do {
            try await http.sendMessage(text)
            draftText = ""
            await loadMessages()
            Log.info("MessageScreen", "已发送：\(text.prefix(20))")
        } catch {
            Log.error("MessageScreen", "发送失败：\(error)")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

public struct ChatMessage: Identifiable {
    public let id: String
    public let time: String
    public let kind: Kind
    /// 真正的消息正文（原来 content 是写死返回空串的计算属性，气泡一直是空的）
    public let text: String

    public enum Kind {
        case system
        case mine
        case theirs(avatar: String)
        case location(systemIcon: String, title: String, subtitle: String)
        case anniversary(days: Int, name: String)
    }

    public var content: String { text }

    public init(time: String, kind: Kind, content: String = "", id: String = UUID().uuidString) {
        self.id = id
        self.time = time
        self.kind = kind
        self.text = content
    }
}

#Preview {
    MessageScreen()
        .environmentObject(AppSession())
        .environmentObject(RelationshipStore(
            me: User(id: "u1", displayName: "我"),
            realtime: HTTPRealtimeSyncService(userId: "u1")
        ))
}
