import SwiftUI
import MapKit
import CoreLocation

/// SwiftUI `Map` 包装（iOS 16+）。
///
/// 设计要点：
/// - API 跟旧的 AAMapView 完全兼容（center / partner / me / zoomLevel / showsUserLocation）
///   → 改 3 处调用点就能完成迁移
/// - 用 WGS-84 坐标（iOS CoreLocation 原生），**不需要 GCJ-02 转换**
/// - 自定义 marker 用 SwiftUI view 渲染（iOS 17+ `Annotation`）/ 系统 marker（iOS 16 fallback）
///
/// 部署目标 iOS 16+。Marker 在 iOS 16 即可用；iOS 17+ 推荐用 `Annotation` 包任意 SwiftUI view。
public struct MapKitView: View {
    public let center: CLLocationCoordinate2D
    public let partner: MapPerson?
    public let me: MapPerson?
    public let zoomLevel: CGFloat
    public let showsUserLocation: Bool
    /// 地图样式（经典 / 卫星 / 混合）—— 对应苹果 MapKit 的 standard / imagery / hybrid
    public let style: MapStyleOption

    @State private var cameraPosition: MapCameraPosition

    /// 地图样式选项
    public enum MapStyleOption: String, CaseIterable, Identifiable {
        case standard, satellite, hybrid

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .standard: return "经典"
            case .satellite: return "卫星"
            case .hybrid: return "混合"
            }
        }

        public var icon: String {
            switch self {
            case .standard: return "map"
            case .satellite: return "globe.asia.australia.fill"
            case .hybrid: return "square.stack.3d.up.fill"
            }
        }

        var mapStyle: MapStyle {
            switch self {
            case .standard: return .standard(elevation: .realistic)
            case .satellite: return .imagery
            case .hybrid: return .hybrid
            }
        }
    }

    public init(
        center: CLLocationCoordinate2D,
        partner: MapPerson? = nil,
        me: MapPerson? = nil,
        zoomLevel: CGFloat = 14,
        showsUserLocation: Bool = true,
        style: MapStyleOption = .standard
    ) {
        self.center = center
        self.partner = partner
        self.me = me
        self.zoomLevel = zoomLevel
        self.showsUserLocation = showsUserLocation
        self.style = style
        // zoomLevel (高德/Google 体系) → MKCoordinateSpan 半径 (米)
        // zoomLevel 14 ≈ 半径 1500m, 15 ≈ 750m, 13 ≈ 3000m
        let radius = zoomLevelToRadius(zoomLevel)
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )))
    }

    public var body: some View {
        Map(position: $cameraPosition) {
            if showsUserLocation {
                UserAnnotation()
            }
            // 伴侣 marker
            if let p = partner {
                Annotation(p.name, coordinate: p.coordinate) {
                    PersonMarkerView(name: p.name, isMe: false)
                }
                .annotationTitles(.hidden)
            }
            // "我" marker（如果不依赖系统蓝点）
            if !showsUserLocation, let m = me {
                Annotation(m.name, coordinate: m.coordinate) {
                    PersonMarkerView(name: m.name, isMe: true)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(style.mapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
            if showsUserLocation {
                MapUserLocationButton()
            }
        }
        .onChange(of: center.latitude, initial: false) { _, _ in updateCamera(animated: true) }
        .onChange(of: center.longitude, initial: false) { _, _ in updateCamera(animated: true) }
        .onAppear { updateCamera(animated: false) }
    }

    private func updateCamera(animated: Bool) {
        let radius = zoomLevelToRadius(zoomLevel)
        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        // MapCameraPosition.region 暂不支持 animated,所以这里统一 instant。
        // SwiftUI 的 .region 过渡本身有动画,但底层不做 setCenter 那种硬切。
        withAnimation(.easeInOut(duration: animated ? 0.35 : 0)) {
            cameraPosition = .region(region)
        }
    }
}

/// 把 AMap/Google 风格的 zoomLevel 转成可视半径（米）。
/// 对照表：zoom 14 ≈ 1.5km, 15 ≈ 750m, 16 ≈ 350m, 12 ≈ 6km, 10 ≈ 25km
private func zoomLevelToRadius(_ zoom: CGFloat) -> CLLocationDistance {
    // 经验公式：radius = 40075000 / 2^(zoom+1)（地球周长 / 2^(zoom+1)）
    return 40_075_000 / pow(2, Double(zoom + 1))
}

// MARK: - 自定义 marker

private struct PersonMarkerView: View {
    let name: String
    let isMe: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(
                        isMe
                            ? AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 0.22, green: 0.52, blue: 0.96),
                                         Color(red: 0.30, green: 0.34, blue: 0.90)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 1.00, green: 0.42, blue: 0.66),
                                         Color(red: 0.62, green: 0.35, blue: 0.95)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .frame(width: 38, height: 38)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(
                        color: (isMe ? Color.blue : Color.pink).opacity(0.45),
                        radius: 6, x: 0, y: 3
                    )
                Image(systemName: isMe ? "person.fill" : "heart.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color(.systemBackground).opacity(0.92))
                        .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                )
                .foregroundColor(.primary)
        }
    }
}

/// 地图上要显示的人。id 用于稳定 identity (SwiftUI diff)。
///
/// 跟旧的 AAMapView.MapPerson 完全兼容（同样 id/name/coordinate），
/// 改完 import 即可继续用。
public struct MapPerson: Equatable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let coordinate: CLLocationCoordinate2D

    public init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }

    public static func == (lhs: MapPerson, rhs: MapPerson) -> Bool {
        // CLLocationCoordinate2D 不自动 Equatable, 手动比
        return lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}


// MARK: - 百度地图（BMKMapView 封装）

/// 百度地图全局管理器（BMKMapManager 必须被强引用，否则会被释放）
final class BaiduMapManager {
    static let shared = BaiduMapManager()

    private let manager = BMKMapManager()
    private(set) var started = false
    private(set) var startSucceeded = false

    /// AK（申请时填的 Bundle ID 必须是 com.lovetrack.app）
    static let apiKey = "jFKhHVyZwSvjVH3F0ARAqZODTMz8XUqL"

    func start() {
        guard !started else { return }
        started = true
        // 延迟到下一轮 runloop：避免在 App.init 期间调用 SDK 导致启动崩溃
        DispatchQueue.main.async {
            self.startSucceeded = self.manager.start(Self.apiKey, generalDelegate: nil)
            Log.info("BaiduMap", "BMKMapManager 启动：\(self.startSucceeded ? "✅ 成功" : "❌ 失败")")
        }
    }
}

/// 百度地图上的一个人
struct BaiduMapPerson: Identifiable, Equatable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let isMe: Bool

    static func == (lhs: BaiduMapPerson, rhs: BaiduMapPerson) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.isMe == rhs.isMe
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// 百度地图容器（SwiftUI 包装 BMKMapView）
struct BaiduMapView: UIViewRepresentable {
    let center: CLLocationCoordinate2D
    let zoomLevel: CGFloat
    let people: [BaiduMapPerson]
    var mapType: BMKMapType = .standard

    func makeUIView(context: Context) -> UIView {
        // AK 校验失败时绝不创建 BMKMapView（百度会直接崩溃，Swift 层捕获不到）
        guard BaiduMapManager.shared.startSucceeded else {
            Log.warn("BaiduMap", "跳过创建 BMKMapView：SDK 未成功初始化")
            let label = UILabel()
            label.text = "百度地图未就绪\nAK 可能不识别当前签名"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabel
            label.backgroundColor = .secondarySystemBackground
            return label
        }

        let map = BMKMapView()
        map.zoomLevel = Float(zoomLevel)
        map.centerCoordinate = center
        map.mapType = mapType
        map.showMapScaleBar = false
        map.isBuildingsEnabled = true
        map.isTrafficEnabled = false
        syncAnnotations(on: map)
        Log.info("BaiduMap", "BMKMapView 已创建 center=(\(center.latitude), \(center.longitude)) zoom=\(zoomLevel)")
        return map
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let map = uiView as? BMKMapView else { return }
        if map.mapType != mapType {
            map.mapType = mapType
        }
        if abs(map.centerCoordinate.latitude - center.latitude) > 1e-7
            || abs(map.centerCoordinate.longitude - center.longitude) > 1e-7 {
            map.centerCoordinate = center
        }
        syncAnnotations(on: map)
    }

    private func syncAnnotations(on map: BMKMapView) {
        if let existing = map.annotations as? [BMKAnnotation] {
            map.removeAnnotations(existing)
        }
        for person in people {
            let p = BMKPointAnnotation()
            p.coordinate = person.coordinate
            p.title = person.name
            map.addAnnotation(p)
        }
    }
}

/// 百度地图实测区块（验证 AK 是否能出图）
struct BaiduMapTestScreen: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var store: RelationshipStore

    @State private var mapType: BMKMapType = .standard

    private var center: CLLocationCoordinate2D {
        if let p = store.lastKnownPartnerLocation {
            return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
        }
        if let me = session.lastLocation?.coordinate {
            return me
        }
        return CLLocationCoordinate2D(latitude: 39.915, longitude: 116.404)
    }

    private var people: [BaiduMapPerson] {
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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            BaiduMapView(center: center, zoomLevel: 15, people: people, mapType: mapType)
                .ignoresSafeArea(edges: .bottom)

            HStack(spacing: 6) {
                ForEach([BMKMapType.standard, .satellite], id: \.rawValue) { t in
                    Button {
                        mapType = t
                    } label: {
                        Text(label(for: t))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(mapType == t ? .white : Theme.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(mapType == t ? Theme.primary : Color.white.opacity(0.92)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    private func label(for t: BMKMapType) -> String {
        switch t {
        case .satellite: return "卫星"
        default: return "经典"
        }
    }
}
