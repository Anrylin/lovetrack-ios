import Foundation
import CoreLocation

/// HTTP + WebSocket 实现的 RealtimeSyncService，对接 Node.js 后端（05-backend）。
///
/// 协议面（RealtimeSyncServiceProtocol）和 InMemoryRealtimeSyncService 一致，
/// 但实际数据走 HTTP 邀请码 / WebSocket 位置同步。
///
/// MVP 限制：
/// - WebSocket 连接断线后只重连 1 次（后续可加重试退避）
/// - 不做 HTTP auth（Demo 阶段够用）
public final class HTTPRealtimeSyncService: RealtimeSyncServiceProtocol, @unchecked Sendable {

    // MARK: - Errors

    public enum ServiceError: Error, LocalizedError {
        case httpStatus(Int, String)
        case decoding(Error)
        case connectionClosed

        public var errorDescription: String? {
            switch self {
            case .httpStatus(let code, let body):
                return "HTTP \(code): \(body)"
            case .decoding(let err):
                return "Decode failed: \(err.localizedDescription)"
            case .connectionClosed:
                return "WebSocket connection closed"
            }
        }
    }

    /// 配对成功回调（从 WebSocket pair_success 或 HTTP pair 回来）
    public var onPairSuccess: ((String) -> Void)?

    /// 被对方锁定时回调：(锁 id, 理由, 到期时间毫秒)
    public var onLockReceived: ((String, String, TimeInterval) -> Void)?

    /// 锁被解除时回调
    public var onLockCleared: (() -> Void)?

    /// 收到对方的截图请求（需要在 UI 上弹确认）
    public var onShotRequest: (() -> Void)?

    /// 对方对我请求的回应（true = 同意，随后会收到 image 消息）
    public var onShotResponse: ((Bool) -> Void)?

    // MARK: - Internal state

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var isConnected = false

    /// 用户 ID
    private let userId: String

    /// 状态锁
    private let lock = NSLock()

    /// 对方位置流（key: userId）
    private var locationStreams: [String: [UUID: AsyncStream<LocationPoint>.Continuation]] = [:]

    /// 对方用户流
    private var partnerStreams: [String: [UUID: AsyncStream<User>.Continuation]] = [:]

    /// 缓存的最新对方位置
    private var latestPartnerLocation: [String: LocationPoint] = [:]

    /// 缓存的 User
    private var users: [String: User] = [:]

    /// 当前已配对关系
    private var relationship: Relationship?

    /// 最近一次创建邀请码返回的真实 code（供 UI 显示）
    public private(set) var latestInviteCode: String = ""

    public init(userId: String) {
        self.userId = userId
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - User

    public func upsertUser(_ user: User) async throws {
        lock.lock()
        users[user.id] = user
        lock.unlock()
        // 不需要后端持久化（demo 用）
    }

    public func observePartnerInfo(userId: String) -> AsyncStream<User> {
        AsyncStream { cont in
            let id = UUID()
            self.lock.lock()
            var dict = self.partnerStreams[userId] ?? [:]
            dict[id] = cont
            self.partnerStreams[userId] = dict
            let initial = self.users[userId]
            self.lock.unlock()
            if let u = initial { cont.yield(u) }
            cont.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.partnerStreams[userId]?.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    // MARK: - Account（LoveLink 账号体系）

    /// token 持久化 key（与 Web 端一致）
    private static let tokenKey = "lovelink.token"

    /// 当前登录 token；nil 表示未登录（只读，写入走 setAuthToken）
    public var authToken: String? {
        UserDefaults.standard.string(forKey: Self.tokenKey)
    }

    private func setAuthToken(_ value: String?) {
        if let v = value, !v.isEmpty {
            UserDefaults.standard.set(v, forKey: Self.tokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        }
    }

    public var isLoggedIn: Bool { (authToken?.isEmpty == false) }

    public func signOut() {
        setAuthToken(nil)
    }

    public struct AuthResult: Sendable {
        public let token: String
        public let userId: String
        public let account: String
        public let nickname: String
        public let emoji: String
        public let coupleCode: String?
        public let paired: Bool
        public let partnerId: String?
        public let partnerName: String?
    }

    /// 注册（POST /api/auth/register）
    @discardableResult
    public func register(
        account: String,
        password: String,
        nickname: String,
        emoji: String = "🐰"
    ) async throws -> AuthResult {
        try await authCall(path: "api/auth/register", body: [
            "account": account,
            "password": password,
            "nickname": nickname,
            "emoji": emoji,
        ])
    }

    /// 登录（POST /api/auth/login）
    @discardableResult
    public func login(account: String, password: String) async throws -> AuthResult {
        try await authCall(path: "api/auth/login", body: [
            "account": account,
            "password": password,
        ])
    }

    private func authCall(path: String, body: [String: Any]) async throws -> AuthResult {
        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        Log.info("LoveLinkAPI", "POST \(req.url?.absoluteString ?? "?")")

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ServiceError.httpStatus(0, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpStatus(http.statusCode, text)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["token"] as? String,
            let user = json["user"] as? [String: Any],
            let userId = user["id"] as? String
        else {
            throw ServiceError.decoding(NSError(domain: "auth", code: 0))
        }

        setAuthToken(token)

        let pairing = json["pairing"] as? [String: Any]
        let partner = pairing?["partner"] as? [String: Any]

        let result = AuthResult(
            token: token,
            userId: userId,
            account: user["account"] as? String ?? "",
            nickname: user["nickname"] as? String ?? "",
            emoji: user["emoji"] as? String ?? "🐰",
            coupleCode: user["coupleCode"] as? String,
            paired: (pairing != nil),
            partnerId: partner?["id"] as? String,
            partnerName: partner?["nickname"] as? String
        )

        // 同步内部 userId / partnerKey，供后续 WS 与位置路由使用
        lock.lock()
        self.actualPartnerKey = result.partnerId
        lock.unlock()
        if let pid = result.partnerId {
            setPartnerKey(pid)
        }

        Log.info("LoveLinkAPI", "登录成功 user=\(userId) 昵称=\(result.nickname) 已配对=\(result.paired)")
        return result
    }

    /// 带鉴权的 GET
    func authedGet(path: String) async throws -> [String: Any] {
        guard let token = authToken else {
            throw ServiceError.httpStatus(401, "not logged in")
        }
        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent(path))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ServiceError.httpStatus(0, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpStatus(http.statusCode, text)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// 带鉴权的 POST/PUT
    @discardableResult
    func authedJSON(
        path: String,
        method: String = "POST",
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let token = authToken else {
            throw ServiceError.httpStatus(401, "not logged in")
        }
        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ServiceError.httpStatus(0, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpStatus(http.statusCode, text)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// 更新我的资料（PUT /api/auth/user/me）
    public func updateMyProfile(nickname: String, emoji: String) async throws {
        try await authedJSON(
            path: "api/auth/user/me",
            method: "PUT",
            body: ["nickname": nickname, "emoji": emoji]
        )
        Log.info("HTTPRealtime", "资料已更新：\(nickname) \(emoji)")
    }

    /// 发送文字消息（POST /api/messages）
    public func sendMessage(_ content: String) async throws {
        try await authedJSON(path: "api/messages", body: ["content": content, "kind": "text"])
    }

    // MARK: - 远程锁定（只锁 App 界面，不涉及系统锁屏）

    /// 锁定对方的 App（POST /api/lock）
    public func lockPartner(reason: String, minutes: Int) async throws {
        try await authedJSON(
            path: "api/lock",
            body: ["reason": reason, "minutes": minutes]
        )
        Log.info("HTTPRealtime", "已锁定 TA：\(reason) / \(minutes) 分钟")
    }

    /// 解锁（POST /api/lock/unlock）
    public func unlockDevice(lockId: String) async throws {
        try await authedJSON(path: "api/lock/unlock", body: ["id": lockId])
        Log.info("HTTPRealtime", "已解锁 \(lockId)")
    }

    /// 我当前是否被锁（GET /api/lock/active）
    public func fetchActiveLock() async throws -> [String: Any]? {
        guard isLoggedIn else { return nil }
        let json = try await authedGet(path: "api/lock/active")
        return json["lock"] as? [String: Any]
    }

    // MARK: - 截图（请求-同意模式）

    /// 请求看对方屏幕（WS 发 shot:req）
    public func requestScreenshot() async throws {
        guard isConnected, let task = task else {
            throw ServiceError.connectionClosed
        }
        let msg: [String: Any] = ["t": "shot:req"]
        let data = try JSONSerialization.data(withJSONObject: msg)
        try await task.send(.string(String(data: data, encoding: .utf8) ?? "{}"))
        Log.info("HTTPRealtime", "📸 已请求对方截图")
    }

    /// 回应对方的截图请求（同意 / 拒绝）
    public func sendShotResponse(accept: Bool) {
        guard isConnected, let task = task else { return }
        let msg: [String: Any] = ["t": "shot:resp", "accept": accept]
        guard let data = try? JSONSerialization.data(withJSONObject: msg),
              let s = String(data: data, encoding: .utf8) else { return }
        Task { try? await task.send(.string(s)) }
        Log.info("HTTPRealtime", "📸 已回应截图请求：\(accept ? "同意" : "拒绝")")
    }

    /// 发送截图（kind=image，content 存 base64 JPEG）
    public func sendImage(_ base64: String) async throws {
        try await authedJSON(path: "api/messages", body: ["content": base64, "kind": "image"])
        Log.info("HTTPRealtime", "📸 截图已上传（\(base64.count / 1024) KB）")
    }

    // MARK: - Pairing

    /// 创建邀请码（调后端 POST /bind）
    public func createPairInvite(code: String, inviter: User) async throws {
        guard let token = authToken else {
            throw ServiceError.httpStatus(401, "未登录，请先注册或登录")
        }
        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent("api/pair/code"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12

        Log.info("HTTPRealtime", "GET \(req.url?.absoluteString ?? "?")")

        do {
            let (data, resp) = try await session.data(for: req)
            Log.info("HTTPRealtime", "got response, status=\((resp as? HTTPURLResponse)?.statusCode ?? 0)")
            guard let http = resp as? HTTPURLResponse else {
                throw ServiceError.httpStatus(0, "no http response")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ServiceError.httpStatus(http.statusCode, body)
            }

            // 解析返回 { code: "...", expiresIn: 600 }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let serverCode = json["code"] as? String else {
                throw ServiceError.decoding(NSError(domain: "decode", code: 0))
            }
            latestInviteCode = serverCode
            Log.info("HTTPRealtime", "bind OK: code=\(serverCode) userId=\(inviter.id)")

            // 后端返回的是 serverCode，不是入参 code —— 入参 code 是占位
            // 我们信任后端返回的 code
            lock.lock()
            relationship = Relationship(
                id: "pending_\(inviter.id)",
                userA: inviter.id,
                userB: "",
                status: .pending,
                pairedAt: Date()
            )
            lock.unlock()

            // 启动 WebSocket
            await connectWebSocket()
        } catch let urlError as URLError {
            Log.warn("HTTPRealtime", "URLError: \(urlError.code.rawValue) - \(urlError.localizedDescription)")
            throw urlError
        }
    }

    /// 用邀请码绑定（调后端 POST /pair）
    public func acceptPairInvite(code: String, invitee: User) async throws -> Relationship {
        guard let token = authToken else {
            throw ServiceError.httpStatus(401, "未登录，请先注册或登录")
        }
        var req = URLRequest(url: BackendConfig.baseURL.appendingPathComponent("api/pair/request"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 12

        // LoveLink 是「请求 → 对方同意」两步，kind 固定 couple
        let body: [String: Any] = ["code": code, "kind": "couple"]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ServiceError.httpStatus(0, "no http response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let errBody = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpStatus(http.statusCode, errBody)
        }

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        // 情况 A：双方互相申请 → 后端直接配对成功
        if let pairing = json["pairing"] as? [String: Any],
           let partner = pairing["partner"] as? [String: Any],
           let pid = partner["id"] as? String, !pid.isEmpty {
            let rel = Relationship(
                id: pairing["id"] as? String ?? "rel_\(pid)",
                userA: invitee.id,
                userB: pid,
                status: .active,
                pairedAt: Date()
            )
            lock.lock()
            relationship = rel
            users[pid] = User(id: pid, displayName: partner["nickname"] as? String ?? "伴侣")
            lock.unlock()
            setPartnerKey(pid)
            Log.info("HTTPRealtime", "配对成功（互相申请）：partnerKey=\(pid)")
            onPairSuccess?(pid)
            await connectWebSocket()
            return rel
        }

        // 情况 B：请求已发出，等对方在 App 里同意（PairScreen 轮询兜底）
        let pendingRel = Relationship(
            id: "pending_\(invitee.id)_\(code)",
            userA: invitee.id,
            userB: "",
            status: .pending,
            pairedAt: Date()
        )
        lock.lock()
        relationship = pendingRel
        lock.unlock()
        Log.info("HTTPRealtime", "配对请求已发送，等待对方同意：code=\(code)")
        await connectWebSocket()
        return pendingRel
    }

    public func dissolveRelationship(id: String) async throws {
        lock.lock()
        relationship = nil
        lock.unlock()
        await disconnectWebSocket()
    }

    // MARK: - Location

    public func uploadPoint(_ point: LocationPoint) async throws {
        let batt = point.battery?.level ?? 1.0
        let charging = point.battery?.isCharging ?? false
        let batteryPct = Int((batt * 100).rounded())
        let moving = (point.speed ?? 0) > 0.6

        // 优先走 WebSocket（延迟最低，服务端会立刻转发给对方）
        if isConnected, let task = task {
            let msg: [String: Any] = [
                "t": "loc",
                "lat": point.lat,
                "lng": point.lon,
                "accuracy": point.horizontalAccuracy,
                "speed": point.speed ?? 0,
                "battery": batteryPct,
                "charging": charging,
                "isMoving": moving,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: msg),
               let str = String(data: data, encoding: .utf8) {
                do {
                    try await task.send(.string(str))
                    return
                } catch {
                    Log.warn("HTTPRealtime", "WS 上报失败，回退 HTTP：\(error.localizedDescription)")
                }
            }
        }

        // WebSocket 不可用时回退 REST，保证位置不丢
        try await authedJSON(path: "api/location/report", body: [
            "lat": point.lat,
            "lng": point.lon,
            "accuracy": point.horizontalAccuracy,
            "speed": point.speed ?? 0,
            "battery": batteryPct,
            "charging": charging,
            "isMoving": moving,
        ])
    }

    public func observePartnerLocation(userId: String) -> AsyncStream<LocationPoint> {
        AsyncStream { cont in
            let id = UUID()
            // 关键修复：用 actualPartnerKey 作为订阅 key，而不是入参 userId。
            // 入参可能是 "partner"（AppSession 的旧调用）或真 partner UUID（RelationshipStore）。
            // 真实 partner_location 缓存时也是用 actualPartnerKey，这样三种调用方式都对得上。
            self.lock.lock()
            let effectiveKey = self.actualPartnerKey ?? userId
            var dict = self.locationStreams[effectiveKey] ?? [:]
            dict[id] = cont
            self.locationStreams[effectiveKey] = dict
            let initial = self.latestPartnerLocation[effectiveKey]
            self.lock.unlock()
            Log.info("HTTPRealtime", "observePartnerLocation(userId=\(userId)) → effective=\(effectiveKey), hasInitial=\(initial != nil)")
            if let p = initial { cont.yield(p) }
            cont.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.locationStreams[effectiveKey]?.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    public func fetchTrackSegment(userId: String, date: Date) async throws -> TrackSegment? {
        // MVP 不实现后端轨迹拉取
        return nil
    }

    /// HTTP 兜底拉取对方最后位置（WebSocket 断线 / 后台被杀 / 服务重启时用）。
    /// GET /location/:userId → { lat, lng, battery, timestamp }
    public func fetchPartnerLocation(userId: String) async throws -> LocationPoint? {
        let url = BackendConfig.baseURL.appendingPathComponent("location/\(userId)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5

        Log.info("HTTPRealtime", "GET \(url.absoluteString)")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            Log.warn("HTTPRealtime", "fetchPartnerLocation: no http response")
            return nil
        }
        // 404 是合法状态（对方还没上报过位置）
        if http.statusCode == 404 {
            Log.info("HTTPRealtime", "fetchPartnerLocation: 404 (no location yet)")
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            Log.warn("HTTPRealtime", "fetchPartnerLocation: HTTP \(http.statusCode) \(body)")
            throw ServiceError.httpStatus(http.statusCode, body)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = json["lat"] as? Double,
              let lng = json["lng"] as? Double else {
            Log.warn("HTTPRealtime", "fetchPartnerLocation: bad payload")
            return nil
        }
        let battery = json["battery"] as? Double ?? 1.0
        let tsMs = json["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
        let timestamp = Date(timeIntervalSince1970: tsMs / 1000)

        let point = LocationPoint(
            userId: userId,
            lat: lat,
            lon: lng,
            altitude: 0,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            speed: -1,
            course: -1,
            timestamp: timestamp,
            receivedAt: Date(),
            battery: BatteryInfo(level: battery, isCharging: false, isLowPower: false),
            source: .gps,
            sessionId: ""
        )
        Log.info("HTTPRealtime", "fetchPartnerLocation: ✅ lat=\(lat), lng=\(lng), battery=\(Int(battery*100))%, age=\(Int(Date().timeIntervalSince(timestamp)))s")

        // 同时更新内部缓存 + 推送给订阅者
        self.lock.lock()
        let key = self.actualPartnerKey ?? userId
        self.latestPartnerLocation[key] = point
        // 兜底：也存到 "partner" key，旧订阅者用得上
        self.latestPartnerLocation["partner"] = point
        let streams = self.locationStreams[key] ?? [:]
        let fallbackStreams = self.locationStreams["partner"] ?? [:]
        self.lock.unlock()
        let totalSubs = streams.count + fallbackStreams.count
        Log.debug("HTTPRealtime", "fetchPartnerLocation: yield to \(totalSubs) subscribers (key=\(key) + fallback)")
        for cont in streams.values { cont.yield(point) }
        for cont in fallbackStreams.values { cont.yield(point) }

        return point
    }

    /// App 启动时拉取自己的关系状态（用于恢复"我是不是 paired"）。
    /// GET /me?userId=xxx → { userId, relationship, partner, lastKnownPartnerLocation, myLastLocation, isOnline }
    /// 返回 nil 表示当前未 paired。
    public func fetchMyState() async throws -> MyState? {
        guard isLoggedIn else {
            Log.info("HTTPRealtime", "fetchMyState: 未登录")
            return nil
        }

        // 一次拿到：配对状态 + 对方最新位置 + 距离
        let dash = try await authedGet(path: "api/dashboard")

        guard let pairing = dash["pairing"] as? [String: Any],
              let partner = pairing["partner"] as? [String: Any],
              let partnerId = partner["id"] as? String,
              !partnerId.isEmpty else {
            Log.info("HTTPRealtime", "fetchMyState: 尚未配对")
            return nil
        }

        let rel = Relationship(
            id: pairing["id"] as? String ?? "rel_\(partnerId)",
            userA: userId,
            userB: partnerId,
            status: .active,
            pairedAt: Date()
        )

        // 解析对方最新位置（dashboard.latest.partner.point）
        var partnerLoc: LocationPoint?
        if let latest = dash["latest"] as? [String: Any],
           let p = latest["partner"] as? [String: Any],
           let point = p["point"] as? [String: Any],
           let lat = point["lat"] as? Double,
           let lng = point["lng"] as? Double {
            let batteryPct = point["battery"] as? Double ?? 100
            let ts = point["at"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
            partnerLoc = LocationPoint(
                userId: partnerId,
                lat: lat,
                lon: lng,
                altitude: 0, horizontalAccuracy: 0, verticalAccuracy: 0,
                speed: -1, course: -1,
                timestamp: Date(timeIntervalSince1970: ts / 1000),
                receivedAt: Date(),
                battery: BatteryInfo(level: batteryPct / 100.0, isCharging: false, isLowPower: false),
                source: .gps, sessionId: ""
            )
        }

        setPartnerKey(partnerId)
        let distText = dash["distanceText"] as? String ?? "-"
        Log.info("HTTPRealtime", "fetchMyState: 已配对 \(partnerId)，有位置=\(partnerLoc != nil)，距离=\(distText)")
        return MyState(relationship: rel, partnerId: partnerId, lastKnownPartnerLocation: partnerLoc)
    }

    public struct MyState: Sendable {
        public let relationship: Relationship
        public let partnerId: String
        public let lastKnownPartnerLocation: LocationPoint?
    }

    /// 实际的 partner userId 缓存（acceptPairInvite 或 pair_success 时设置）。
    /// 修这个之前 observePartnerLocation(userId: "partner") 是个 magic string，
    /// 实际 RelationshipStore.startObservingPartner 用的是真 partner UUID，对不上。
    /// 现在统一用 actualPartnerKey 路由。
    private var actualPartnerKey: String?

    public func setPartnerKey(_ userId: String?) {
        lock.lock()
        let oldKey = actualPartnerKey
        actualPartnerKey = userId
        // 如果 partner 变了，把旧的 latest 迁移过来（避免切换时丢位置）
        if oldKey != userId, let userId = userId {
            if let oldLoc = latestPartnerLocation[oldKey ?? "partner"] {
                latestPartnerLocation[userId] = oldLoc
            }
        }
        lock.unlock()
        // 🐛 Bug 排查:不要把自己设成 partnerKey。
        if userId == self.userId {
            Log.error("HTTPRealtime", "🐛 BUG: setPartnerKey(\(userId ?? "nil")) 但 self.userId 也是 \(self.userId)!")
        }
        Log.info("HTTPRealtime", "partnerKey set: \(userId ?? "nil") (was: \(oldKey ?? "nil"))")
    }

    // MARK: - WebSocket

    /// 在 App 启动时提前连 WS（不依赖配对）
    public func bootstrapConnect() async {
        Log.info("HTTPRealtime", "bootstrapConnect called")
        await connectWebSocket()
    }

    private func connectWebSocket() async {
        guard task == nil else { return }
        guard let token = authToken else {
            Log.warn("HTTPRealtime", "未登录，跳过 WebSocket 连接（先注册/登录）")
            return
        }
        var comps = URLComponents(url: BackendConfig.wsURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = comps.url else { return }

        let newTask = session.webSocketTask(with: url)
        self.task = newTask
        newTask.resume()
        isConnected = true
        Log.info("HTTPRealtime", "WebSocket connecting to \(url.absoluteString)")
        // 后台跑接收循环（不要 await，否则会阻塞外层）
        Task { await self.receiveLoop() }
    }

    private func disconnectWebSocket() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func receiveLoop() async {
        guard let task = task else { return }
        do {
            while true {
                let msg = try await task.receive()
                switch msg {
                case .string(let s):
                    handleServerMessage(s)
                case .data(let d):
                    if let s = String(data: d, encoding: .utf8) {
                        handleServerMessage(s)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            Log.warn("HTTPRealtime", "WebSocket error: \(error.localizedDescription)")
            isConnected = false
        }
    }

    private func handleServerMessage(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = msg["type"] as? String else {
            Log.warn("HTTPRealtime", "⚠️ 无法解析服务端消息: \(raw.prefix(120))")
            return
        }

        switch type {
        case "hello":
            // 连接握手：后端告知我是谁、伴侣是谁
            let partnerObj = msg["partner"] as? [String: Any]
            if let pid = partnerObj?["id"] as? String, !pid.isEmpty {
                self.lock.lock()
                self.actualPartnerKey = pid
                self.lock.unlock()
                setPartnerKey(pid)
                Log.info("HTTPRealtime", "hello → partnerKey=\(pid)")
            } else {
                Log.info("HTTPRealtime", "hello → 当前未配对")
            }

        case "partner:loc":
            guard let payload = msg["point"] as? [String: Any],
                  let lat = payload["lat"] as? Double,
                  let lng = payload["lng"] as? Double else {
                Log.warn("HTTPRealtime", "partner:loc 缺坐标")
                return
            }
            // LoveLink 的 battery 是 0-100 整数，时间字段是 at（毫秒）
            let batteryPct = payload["battery"] as? Double ?? 100
            let ts = payload["at"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
            let timestamp = Date(timeIntervalSince1970: ts / 1000)

            // 用 actualPartnerKey 路由（避免 RelationshipStore 和 AppSession 订阅对不上）
            self.lock.lock()
            let partnerKey = self.actualPartnerKey ?? "partner"
            self.lock.unlock()

            // 🐛 Bug 排查:打印接收方 / partnerKey / 实际收到的坐标。
            // 之前 bug = "A看A正确但A看B不正确",这条日志会显示 iOS 是否真的拿到了对方的坐标。
            Log.info("HTTPRealtime", "📍 partner:loc 收: 接收方=\(self.userId) partnerKey=\(partnerKey) lat=\(lat) lng=\(lng) bat=\(Int(batteryPct))% age=\(Int(Date().timeIntervalSince(timestamp)))s")

            // 🐛 防御:partnerLocation 不应该是自己。如果 partnerKey 跟自己一致,
            // 说明 actualPartnerKey 没正确初始化(典型症状:A 的 marker 显示在 A 自己的位置上)。
            if partnerKey == self.userId {
                Log.error("HTTPRealtime", "🐛 BUG: partnerKey(\(partnerKey)) == self.userId(\(self.userId))! 收到的 partner_location 会被当成自己的位置。actualPartnerKey 路由错乱。")
            }

            let point = LocationPoint(
                userId: partnerKey,
                lat: lat,
                lon: lng,
                altitude: 0,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                speed: -1,
                course: -1,
                timestamp: timestamp,
                receivedAt: Date(),
                battery: BatteryInfo(level: batteryPct / 100.0, isCharging: false, isLowPower: false),
                source: .gps,
                sessionId: ""
            )

            lock.lock()
            latestPartnerLocation[partnerKey] = point
            // 兜底：也存到 "partner" key，兼容老的 AppSession 订阅
            latestPartnerLocation["partner"] = point
            // 🐛 BUG FIX: 当 partnerKey == "partner" 时,streams 和 fallbackStreams 是同一个 dict,
            // 双重迭代会把每个订阅者 yield 两次 → refreshPartnerLocation 被调 2 次 → 日志里 "subscribers=2" 是误报。
            // 改为用 Set 去重 + 一次 yield。
            let primaryStreams = locationStreams[partnerKey] ?? [:]
            let fallbackStreams = partnerKey == "partner" ? [:] : (locationStreams["partner"] ?? [:])
            let allContinuations: [UUID: AsyncStream<LocationPoint>.Continuation] =
                primaryStreams.merging(fallbackStreams) { _, new in new }
            let subscriberCount = allContinuations.count
            lock.unlock()

            Log.info("HTTPRealtime", "📍 partner_location 派发: point.userId=\(point.userId) point.lat=\(point.lat) point.lon=\(point.lon) → subscribers=\(subscriberCount) (key=\(partnerKey)+partner)")
            for cont in allContinuations.values { cont.yield(point) }

        case "pong":
            Log.debug("HTTPRealtime", "pong received")

        case "paired":
            Log.info("HTTPRealtime", "🎉 paired 收到！")
            let partnerObj = msg["partner"] as? [String: Any]
            let newPartnerId = partnerObj?["id"] as? String ?? ""
            if !newPartnerId.isEmpty, newPartnerId != self.userId {
                let partnerName = partnerObj?["nickname"] as? String ?? "伴侣"
                self.lock.lock()
                self.users[newPartnerId] = User(id: newPartnerId, displayName: partnerName)
                self.relationship = Relationship(
                    id: "rel_\(self.userId)_\(newPartnerId)",
                    userA: self.userId,
                    userB: newPartnerId,
                    status: .active,
                    pairedAt: Date()
                )
                self.lock.unlock()
                self.setPartnerKey(newPartnerId)
                Log.info("HTTPRealtime", "paired → partnerKey=\(newPartnerId) 昵称=\(partnerName)")
            }
            onPairSuccess?(newPartnerId)

        case "unpaired":
            Log.info("HTTPRealtime", "关系已解除")
            self.lock.lock()
            self.relationship = nil
            self.lock.unlock()
            self.setPartnerKey(nil)
            onPairSuccess?("")

        case "partner:status":
            let sharing = msg["sharing"] as? Int
            let battery = msg["battery"] as? Int
            Log.info("HTTPRealtime", "partner:status sharing=\(sharing.map(String.init) ?? "-") battery=\(battery.map(String.init) ?? "-")")

        case "presence":
            let online = msg["online"] as? Bool ?? false
            Log.info("HTTPRealtime", "presence online=\(online)")

        case "loc:ack", "status:ack":
            break

        case "lock":
            let lockObj = msg["lock"] as? [String: Any] ?? [:]
            if let id = lockObj["id"] as? String,
               let untilAt = lockObj["untilAt"] as? TimeInterval {
                let reason = lockObj["reason"] as? String ?? "乖乖听话"
                Log.info("HTTPRealtime", "🔒 被锁定：\(reason)")
                onLockReceived?(id, reason, untilAt)
            }

        case "lock:done":
            Log.info("HTTPRealtime", "🔓 锁已解除")
            onLockCleared?()

        case "shot:req":
            Log.info("HTTPRealtime", "📸 收到对方的截图请求")
            onShotRequest?()

        case "shot:resp":
            let accept = msg["accept"] as? Bool ?? false
            Log.info("HTTPRealtime", "📸 对方回应截图请求：\(accept ? "同意" : "拒绝")")
            onShotResponse?(accept)

        default:
            Log.warn("HTTPRealtime", "未处理的消息类型: \(type)")
        }
    }
}