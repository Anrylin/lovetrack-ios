import Foundation
import CoreLocation
import SwiftUI

/// 轨迹回放视图。
///
/// 数据流：ViewModel 拉取当天 `TrackSegment` → 显示折线 + 时间轴拖动。
public struct TrackPlaybackView: View {
    @ObservedObject var viewModel: TrackPlaybackViewModel

    public init(viewModel: TrackPlaybackViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            dateBar
            Divider()
            mapArea
            Divider()
            timelineArea
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - 横向日期选择

    private var dateBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(viewModel.availableDates, id: \.self) { date in
                    dateChip(date)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func dateChip(_ date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
        return Button {
            Task { await viewModel.selectDate(date) }
        } label: {
            VStack(spacing: 2) {
                Text(date, format: .dateTime.day())
                    .font(.headline)
                Text(date, format: .dateTime.weekday(.short))
                    .font(.caption2)
            }
            .frame(width: 44, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple.opacity(0.15) : Color.gray.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.purple : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(isSelected ? Color.purple : Color.primary)
        }
    }

    // MARK: - 地图区

    private var mapArea: some View {
        MapView(
            center: viewModel.currentCoordinate ?? CLLocationCoordinate2D(latitude: 36.6512, longitude: 117.1201),
            annotations: viewModel.annotations,
            polyline: viewModel.polyline,
            showsUserLocation: false
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - 时间轴

    private var timelineArea: some View {
        VStack(spacing: 8) {
            HStack {
                Text(viewModel.currentTime, style: .time)
                    .font(.headline.monospacedDigit())
                Spacer()
                Text(String(format: "%.1f km", viewModel.totalDistanceKm))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { viewModel.playheadFraction },
                    set: { fraction in
                        Task { await viewModel.setPlayhead(fraction: fraction) }
                    }
                ),
                in: 0...1
            )
            .tint(.purple)
        }
        .padding(16)
    }
}

@MainActor
public final class TrackPlaybackViewModel: ObservableObject {
    @Published public private(set) var availableDates: [Date] = []
    @Published public var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published public private(set) var currentTime: Date = Date()
    @Published public private(set) var polyline: [CLLocationCoordinate2D] = []
    @Published public private(set) var annotations: [MapView.MapItem] = []
    @Published public private(set) var totalDistanceKm: Double = 0
    @Published public private(set) var playheadFraction: Double = 0
    @Published public private(set) var currentCoordinate: CLLocationCoordinate2D? = nil

    private let sync: RealtimeSyncServiceProtocol
    private var currentSegment: TrackSegment?

    public init(sync: RealtimeSyncServiceProtocol) {
        self.sync = sync
    }

    /// 日期格式（后端按东八区切天）
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f
    }()

    /// 拉取有轨迹的日期（原来这里是凭空编的最近 7 天）
    public func load() async {
        guard let http = sync as? HTTPRealtimeSyncService, http.isLoggedIn else {
            availableDates = []
            await selectDate(Date())
            return
        }
        do {
            let json = try await http.authedGet(path: "api/location/days")
            let days = (json["days"] as? [String]) ?? []
            availableDates = days.compactMap { Self.dayFormatter.date(from: $0) }
            Log.info("TrackPlayback", "有轨迹的天数：\(availableDates.count)（\(days.joined(separator: ","))）")

            if let first = availableDates.first {
                await selectDate(first)
            } else {
                let today = Calendar.current.startOfDay(for: Date())
                availableDates = [today]
                await selectDate(today)
            }
        } catch {
            Log.warn("TrackPlayback", "加载轨迹日期失败：\(error.localizedDescription)")
        }
    }

    /// 拉取某天的真实轨迹点（原来调的是已失效的 fetchTrackSegment + 写死 userId "me"）
    public func selectDate(_ date: Date) async {
        selectedDate = Calendar.current.startOfDay(for: date)

        guard let http = sync as? HTTPRealtimeSyncService, http.isLoggedIn else {
            polyline = []
            annotations = []
            currentSegment = nil
            totalDistanceKm = 0
            return
        }

        let dayStr = Self.dayFormatter.string(from: selectedDate)
        do {
            let json = try await http.authedGet(path: "api/location/history?day=\(dayStr)")
            let rows = (json["points"] as? [[String: Any]]) ?? []
            let uid = json["userId"] as? String ?? ""

            let pts: [LocationPoint] = rows.compactMap { r in
                guard let lat = r["lat"] as? Double, let lng = r["lng"] as? Double else { return nil }
                let at = r["at"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000
                let batt = r["battery"] as? Double
                return LocationPoint(
                    id: r["id"] as? String ?? UUID().uuidString,
                    userId: uid,
                    lat: lat,
                    lon: lng,
                    horizontalAccuracy: r["accuracy"] as? Double ?? 0,
                    speed: r["speed"] as? Double,
                    course: r["heading"] as? Double,
                    timestamp: Date(timeIntervalSince1970: at / 1000),
                    battery: batt.map { BatteryInfo(level: $0 / 100.0, isCharging: false, isLowPower: false) },
                    source: .gps,
                    sessionId: ""
                )
            }

            polyline = pts.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }

            var anns: [MapView.MapItem] = []
            if let first = pts.first {
                anns.append(MapView.MapItem(
                    id: "start",
                    coordinate: .init(latitude: first.lat, longitude: first.lon),
                    title: "起点",
                    iconSystemName: "flag.circle.fill"
                ))
            }
            if pts.count > 1, let last = pts.last {
                anns.append(MapView.MapItem(
                    id: "end",
                    coordinate: .init(latitude: last.lat, longitude: last.lon),
                    title: "终点",
                    iconSystemName: "flag.checkered.circle.fill"
                ))
            }
            annotations = anns

            // 轨迹总长（相邻点累加）
            var dist: Double = 0
            if pts.count > 1 {
                for i in 1..<pts.count {
                    let a = CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon)
                    let b = CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
                    dist += a.distance(from: b)
                }
            }
            totalDistanceKm = dist / 1000

            if let first = pts.first, let last = pts.last {
                currentSegment = TrackSegment(
                    userId: uid,
                    startedAt: first.timestamp,
                    endedAt: last.timestamp,
                    points: pts,
                    summary: TrackSegment.Summary(
                        distanceMeters: dist,
                        topSpeed: pts.compactMap { $0.speed }.max() ?? 0,
                        avgSpeed: dist / Double(max(1, pts.count)),
                        polylineEncoded: ""
                    )
                )
                currentTime = first.timestamp
            } else {
                currentSegment = nil
                currentTime = selectedDate
            }
            playheadFraction = 0
            Log.info("TrackPlayback", "\(dayStr) 轨迹 \(pts.count) 个点，总长 \(String(format: "%.2f", totalDistanceKm)) km")
        } catch {
            Log.warn("TrackPlayback", "加载 \(dayStr) 轨迹失败：\(error.localizedDescription)")
            polyline = []
            annotations = []
            currentSegment = nil
            totalDistanceKm = 0
        }
    }

    public func setPlayhead(fraction: Double) async {
        playheadFraction = max(0, min(1, fraction))
        guard let seg = currentSegment, !seg.points.isEmpty else { return }
        let idx = Int(Double(seg.points.count - 1) * playheadFraction)
        let p = seg.points[idx]
        currentTime = p.timestamp
    }
}
