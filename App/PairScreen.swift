import SwiftUI
import CoreLocation
import Foundation

/// 配对屏幕（创建邀请码 / 输入邀请码）。
///
/// Day 1 demo：用户首次打开 App → 看到这个屏幕
///   - A 点"创建邀请码" → 拿到 6 位码
///   - B 点"输入邀请码" → 输入 A 的码 → 双方绑定
///
/// 未配对时也显示 mini 地图（仅自己位置），让用户验证 app 真的在定位
public struct PairScreen: View {
    @EnvironmentObject var session: AppSession
    @State private var mode: Mode = .home
    @State private var inviteCode: String = ""
    @State private var inputCode: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    /// inviter 停在邀请码页等待对方加入时的轮询任务（WS 推送之外的兜底）
    @State private var pollTask: Task<Void, Never>?

    enum Mode {
        case home          // 默认：两个按钮
        case create        // 创建邀请码后展示
        case join          // 输入邀请码
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.36, blue: 0.61),
                        Color(red: 0.55, green: 0.36, blue: 0.96)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content
                    .padding(24)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .home: homeView
        case .create: createView
        case .join: joinView
        }
    }

    // MARK: - Home

    private var homeView: some View {
        VStack(spacing: 20) {
            // 顶部标题
            VStack(spacing: 8) {
                Text("💕")
                    .font(.system(size: 64))
                Text("LoveTrack")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                Text("和 TA 保持连接")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 16)

            // ⬇️ mini 地图: 未配对时也能验证 app 真在定位
            if let me = session.lastLocation {
                MapKitView(
                    center: me.coordinate,
                    partner: nil,
                    me: MapPerson(
                        id: session.currentUser.id,
                        name: "我",
                        coordinate: me.coordinate
                    ),
                    zoomLevel: 15
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                )
                .softShadow(Theme.shadowMd)
                .padding(.horizontal, 8)
            }

            Spacer()

            // 底部按钮
            VStack(spacing: 16) {
                Button {
                    Task { await createInvite() }
                } label: {
                    HStack {
                        Image(systemName: "qrcode")
                        Text("创建邀请码")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .foregroundStyle(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    mode = .join
                } label: {
                    HStack {
                        Image(systemName: "keyboard")
                        Text("输入邀请码")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.2))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white, lineWidth: 2)
                    )
                }

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .padding(.top, 8)
                }

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(.top, 8)
                }
            }

            Spacer()
        }
    }

    // MARK: - Create

    private var createView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🎉")
                .font(.system(size: 80))

            Text("你的邀请码")
                .font(.title2)
                .foregroundStyle(.white)

            Text(inviteCode)
                .font(.system(size: 56, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.vertical, 20)
                .padding(.horizontal, 32)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white, lineWidth: 3)
                )

            Text("把这个码发给 TA\n10 分钟内有效")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))

            Spacer()

            Button {
                Task { await enterAppNow() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView().tint(Color.purple)
                    } else {
                        Text("进入 App").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .foregroundStyle(Color.purple)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(isLoading)

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
            }

            Text("TA 输入邀请码后会自动进入，通常不用手动点")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))

            Button("返回") {
                pollTask?.cancel()
                pollTask = nil
                mode = .home
                inviteCode = ""
                errorMessage = nil
            }
            .foregroundStyle(.white.opacity(0.8))
        }
        .onAppear { startWaitingForPartner() }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Join

    private var joinView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🔗")
                .font(.system(size: 80))

            Text("输入 TA 的邀请码")
                .font(.title2)
                .foregroundStyle(.white)

            TextField("6 位邀请码", text: $inputCode)
                .font(.system(size: 32, weight: .heavy, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 16)
                .padding(.horizontal, 24)
                .background(Color.white)
                .foregroundStyle(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onChange(of: inputCode) { new in
                    inputCode = String(new.prefix(6)).uppercased()
                }

            Spacer()

            Button {
                Task { await joinWithCode() }
            } label: {
                Text("绑定")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .foregroundStyle(Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .disabled(inputCode.count != 6 || isLoading)

            if isLoading {
                ProgressView().tint(.white)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            Button("返回") { mode = .home }
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // MARK: - Actions

    private func createInvite() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // DEBUG 和 RELEASE 都走后端真配对 —— 两台真机测试时需要 server 知道谁跟谁配对了
        // 才能在 location_update 时把 partner_location 推给对方
        do {
            let code = try await session.relationshipStore.generatePairCode()
            inviteCode = code
            mode = .create
            Log.info("PairScreen", "✅ 创建邀请码成功: \(code)")
        } catch {
            errorMessage = friendlyMessage(error)
            Log.error("PairScreen", "❌ 创建邀请码失败: \(error)")
        }
    }

    private func joinWithCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // DEBUG 和 RELEASE 都走后端真绑定 —— 输任意 6 位并不会通过，
        // 后端只接受由 /bind 生成的真实邀请码
        do {
            try await session.relationshipStore.acceptPairCode(inputCode)
            session.completePairing()
            Log.info("PairScreen", "✅ 绑定成功: code=\(inputCode)")
        } catch {
            errorMessage = friendlyMessage(error)
            Log.error("PairScreen", "❌ 绑定失败: \(error)")
        }
    }

    // MARK: - Waiting / Enter

    /// inviter 停在邀请码页时，每 4 秒向后端确认一次「TA 加入了没」。
    ///
    /// 后端是 in-memory 的，WebSocket 的 pair_success 在几种情况下会漏推
    /// （服务端重启、WS 断线重连窗口期、NAT 超时），只靠推送会让邀请方永远卡在这一页。
    /// 这里用 HTTP /me 做兜底，最多等 3 分钟。
    @MainActor
    private func startWaitingForPartner() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            for i in 1...45 {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { return }
                let paired = await session.refreshPairingFromServer()
                if paired {
                    Log.info("PairScreen", "✅ 轮询第 \(i) 次检测到 TA 已加入，自动进入主页")
                    self.isLoading = false
                    return
                }
            }
            Log.info("PairScreen", "等待对方加入超时（约 3 分钟），可让 TA 重新输入或重新生成码")
        }
    }

    /// 点「进入 App」：先向后端核实是否真的已配对，避免进入"半配对"状态。
    @MainActor
    private func enterAppNow() async {
        isLoading = true
        errorMessage = nil

        let paired = await session.refreshPairingFromServer()

        isLoading = false
        if paired {
            pollTask?.cancel()
            pollTask = nil
            Log.info("PairScreen", "✅ 服务端确认已配对，进入主页")
        } else {
            errorMessage = "TA 还没输入邀请码。\n让 TA 输入上面的码，这里会自动进入。"
            Log.info("PairScreen", "进入 App 被拦下：服务端显示尚未配对")
        }
    }

    /// 把网络/服务端错误翻译成用户看得懂的话（原始 NSError 对用户没意义）。
    private func friendlyMessage(_ error: Error) -> String {
        if let e = error as? HTTPRealtimeSyncService.ServiceError {
            switch e {
            case let .httpStatus(code, body):
                switch code {
                case 0:
                    return "连不上服务器，检查网络"
                case 400:
                    return "不能和自己配对，或参数有误"
                case 404:
                    return "邀请码不存在（可能已被使用，或服务器重启过）"
                case 409:
                    return "这个邀请码已经被别人用掉了"
                case 410:
                    return "邀请码已过期（10 分钟有效），让 TA 重新生成"
                default:
                    let detail = body.isEmpty ? "" : "：\(body.prefix(50))"
                    return "服务器返回 \(code)\(detail)"
                }
            case .decoding:
                return "服务器返回格式异常"
            case .connectionClosed:
                return "连接已断开，请重试"
            }
        }
        if let u = error as? URLError {
            switch u.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "连不上服务器（\(BackendConfig.baseURL.host ?? "?")）"
            case .timedOut:
                return "请求超时，网络不太好"
            case .notConnectedToInternet:
                return "设备没有联网"
            case .appTransportSecurityRequiresSecureConnection:
                return "被 iOS 的 ATS 拦下（后端地址不是 https）"
            default:
                return "网络错误：\(u.localizedDescription)"
            }
        }
        return error.localizedDescription
    }
}

// MARK: - 登录 / 注册（LoveLink 账号体系）

/// 未登录时显示：注册或登录，成功后直接进入主页（配对不再拦截启动流程）。
struct AuthScreen: View {
    @EnvironmentObject var session: AppSession

    @State private var mode: Mode = .login
    @State private var account = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var emoji = "🐰"
    @State private var isLoading = false
    @State private var errorMessage: String?

    enum Mode { case login, register }

    private let emojis = ["🐰", "🐻", "🐱", "🐶", "🦊", "🐼", "🐨", "🐯", "🦁", "🐸"]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.36, blue: 0.61),
                    Color(red: 0.55, green: 0.36, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    Spacer(minLength: 36)

                    Text("💕").font(.system(size: 60))
                    Text("LoveTrack").font(.largeTitle.bold()).foregroundStyle(.white)
                    Text(mode == .login ? "登录你的账号" : "创建一个新账号")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))

                    VStack(spacing: 12) {
                        TextField("账号（3-32 位字母或数字）", text: $account)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)

                        SecureField("密码（至少 6 位）", text: $password)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)

                        if mode == .register {
                            TextField("昵称（TA 看到的名字）", text: $nickname)
                                .padding()
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(emojis, id: \.self) { e in
                                        Button {
                                            emoji = e
                                        } label: {
                                            Text(e)
                                                .font(.system(size: 24))
                                                .frame(width: 44, height: 44)
                                                .background(emoji == e ? Color.white : Color.white.opacity(0.3))
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 6)

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.yellow)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView().tint(Color.purple)
                            } else {
                                Text(mode == .login ? "登录" : "注册并开始")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white)
                        .foregroundStyle(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isLoading || account.count < 3 || password.count < 6)

                    Button(mode == .login ? "没有账号？去注册" : "已有账号？去登录") {
                        mode = (mode == .login) ? .register : .login
                        errorMessage = nil
                    }
                    .foregroundStyle(.white.opacity(0.85))

                    Text("账号只在你和 TA 之间共享位置；密码加密存储，不会外传")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.6))

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
            }
        }
    }

    @MainActor
    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let http = session.realtime as? HTTPRealtimeSyncService else {
            errorMessage = "网络层未初始化"
            return
        }

        do {
            let result: HTTPRealtimeSyncService.AuthResult
            if mode == .login {
                result = try await http.login(account: account, password: password)
            } else {
                result = try await http.register(
                    account: account,
                    password: password,
                    nickname: nickname.isEmpty ? account : nickname,
                    emoji: emoji
                )
            }
            session.markLoggedIn(result)
            Log.info("AuthScreen", "\(mode == .login ? "登录" : "注册")成功：\(result.nickname)")
        } catch {
            errorMessage = friendly(error)
            Log.error("AuthScreen", "失败: \(error)")
        }
    }

    private func friendly(_ error: Error) -> String {
        if let e = error as? HTTPRealtimeSyncService.ServiceError {
            switch e {
            case let .httpStatus(code, body):
                switch code {
                case 401: return "账号或密码不正确"
                case 409: return "这个账号已经被注册了"
                case 400: return "账号或密码格式不对（账号 3-32 位，密码至少 6 位）"
                case 0: return "连不上服务器，检查网络"
                default: return "服务器返回 \(code)\(body.isEmpty ? "" : "：\(body.prefix(50))")"
                }
            case .decoding: return "服务器返回格式异常"
            case .connectionClosed: return "连接已断开，请重试"
            }
        }
        if let u = error as? URLError {
            return "网络错误：\(u.localizedDescription)"
        }
        return error.localizedDescription
    }
}