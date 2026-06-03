import ActivityKit
import CryptoKit
import SwiftUI
import WidgetKit

// Mesmo contrato do plugin `live_activities` (README: nome EXATO + ContentState).
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState

  public struct ContentState: Codable, Hashable {
    var appGroupId: String
  }

  var id = UUID()
}

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    "\(id)_\(key)"
  }
}

// App Group — leitura direta como no exemplo oficial do plugin.
private let kAppGroupId = "group.com.dreamkeys.corretor"
private let kActivityName = "checkin"
private let sharedDefaults = UserDefaults(suiteName: kAppGroupId)

// Chaves fixas gravadas pelo Runner (MethodChannel) + fallbacks do plugin.
private enum IslandKey {
  static let userName = "island_userName"
  static let statusPhase = "island_statusPhase"
  static let expiresAtEpoch = "island_expiresAtEpoch"
  static let checkedInAtEpoch = "island_checkedInAtEpoch"
}

// Paleta estilo delivery (iFood): pill colorida + ícone em círculo + timer em destaque.
private enum Brand {
  static let active = Color(red: 0.86, green: 0.15, blue: 0.15)       // vermelho marca
  static let activeAlt = Color(red: 0.98, green: 0.45, blue: 0.09)    // laranja
  static let ok = Color(red: 0.06, green: 0.73, blue: 0.51)           // check-in ok
  static let warn = Color(red: 0.96, green: 0.62, blue: 0.04)
  static let urgent = Color(red: 0.98, green: 0.45, blue: 0.09)
  static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)
  static let pillBg = Color(red: 0.12, green: 0.12, blue: 0.14)
}

private enum Phase: String {
  case active, expiring, critical, expired

  static func from(_ raw: String?) -> Phase {
    switch raw?.lowercased() {
    case "expiring": return .expiring
    case "critical": return .critical
    case "expired": return .expired
    default: return .active
    }
  }

  var accent: Color {
    switch self {
    case .active: return Brand.ok
    case .expiring: return Brand.warn
    case .critical: return Brand.urgent
    case .expired: return Brand.danger
    }
  }

  var shortLabel: String {
    switch self {
    case .active: return "Na imob."
    case .expiring: return "Expira"
    case .critical: return "Urgente"
    case .expired: return "Expirou"
    }
  }

  var title: String {
    switch self {
    case .active: return "Check-in ativo"
    case .expiring: return "Expira em breve"
    case .critical: return "Check-in urgente"
    case .expired: return "Check-in expirado"
    }
  }

  var symbol: String {
    switch self {
    case .active: return "building.2.fill"
    case .expiring: return "clock.badge.exclamationmark.fill"
    case .critical: return "exclamationmark.triangle.fill"
    case .expired: return "xmark.circle.fill"
    }
  }
}

private func uuid5(namespace: UUID, name: String) -> UUID {
  var data = withUnsafeBytes(of: namespace.uuid) { Data($0) }
  data.append(Data(name.utf8))
  let hash = Insecure.SHA1.hash(data: data)
  var bytes = Array(hash.prefix(16))
  bytes[6] = (bytes[6] & 0x0F) | 0x50
  bytes[8] = (bytes[8] & 0x3F) | 0x80
  return UUID(uuid: uuid_t(
    bytes[0], bytes[1], bytes[2], bytes[3],
    bytes[4], bytes[5], bytes[6], bytes[7],
    bytes[8], bytes[9], bytes[10], bytes[11],
    bytes[12], bytes[13], bytes[14], bytes[15]
  ))
}

private let kNamespaceDNS = UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!

private struct Snap {
  let name: String
  let expires: Date
  let phase: Phase

  init(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) {
    let ud = sharedDefaults
    let pluginId = uuid5(namespace: kNamespaceDNS, name: kActivityName)

    func str(_ field: String) -> String? {
      if let ud = ud {
        if field == "userName", let v = ud.string(forKey: IslandKey.userName), !v.isEmpty { return v }
        if field == "statusPhase", let v = ud.string(forKey: IslandKey.statusPhase), !v.isEmpty { return v }

        let keys = [
          context.attributes.prefixedKey(field),
          "\(pluginId.uuidString)_\(field)",
          "\(pluginId)_\(field)",
          "\(context.attributes.id.uuidString)_\(field)",
        ]
        for k in keys {
          if let s = ud.string(forKey: k), !s.trimmingCharacters(in: .whitespaces).isEmpty {
            return s.trimmingCharacters(in: .whitespaces)
          }
        }
        let suffix = "_\(field)"
        for (k, v) in ud.dictionaryRepresentation() {
          guard k.hasSuffix(suffix) else { continue }
          if let s = v as? String, !s.isEmpty { return s }
        }
      }
      return nil
    }

    func epoch(_ field: String) -> Double {
      if let ud = ud {
        if field == "expiresAtEpoch", let s = ud.string(forKey: IslandKey.expiresAtEpoch), let d = Double(s) { return d }
        if field == "checkedInAtEpoch", let s = ud.string(forKey: IslandKey.checkedInAtEpoch), let d = Double(s) { return d }

        let keys = [
          context.attributes.prefixedKey(field),
          "\(pluginId.uuidString)_\(field)",
          "\(pluginId)_\(field)",
        ]
        for k in keys {
          if let n = ud.object(forKey: k) as? NSNumber { return n.doubleValue }
          if let s = ud.string(forKey: k), let d = Double(s) { return d }
        }
        let suffix = "_\(field)"
        for (k, v) in ud.dictionaryRepresentation() {
          guard k.hasSuffix(suffix) else { continue }
          if let n = v as? NSNumber { return n.doubleValue }
          if let s = v as? String, let d = Double(s) { return d }
        }
      }
      return 0
    }

    name = {
      if let u = ud?.string(forKey: IslandKey.userName), !u.isEmpty { return u }
      return str("userName") ?? "Corretor"
    }()

    let expiresMs = {
      if let s = ud?.string(forKey: IslandKey.expiresAtEpoch), let d = Double(s), d > 0 { return d }
      return epoch("expiresAtEpoch")
    }()

    expires = expiresMs > 0
      ? Date(timeIntervalSince1970: expiresMs / 1000.0)
      : Date().addingTimeInterval(2 * 3600)

    phase = Phase.from({
      if let p = ud?.string(forKey: IslandKey.statusPhase), !p.isEmpty { return p }
      return str("statusPhase")
    }())

    let left = expires.timeIntervalSinceNow
    if left <= 1 { phase = .expired }
    else if left < 5 * 60 { phase = .critical }
    else if left < 15 * 60, phase == .active { phase = .expiring }
  }

  var timerText: String {
    let sec = max(0, Int(expires.timeIntervalSinceNow))
    let m = sec / 60
    let s = sec % 60
    if m >= 60 {
      let h = m / 60
      let rm = m % 60
      return rm > 0 ? String(format: "%dh%02dm", h, rm) : String(format: "%dh", h)
    }
    return String(format: "%d:%02d", m, s)
  }
}

// MARK: - UI (iFood-like: círculo colorido + pill escura + texto branco)

private struct BrandBadge: View {
  let phase: Phase
  var diameter: CGFloat = 28

  var body: some View {
    ZStack {
      Circle()
        .fill(phase.accent)
        .frame(width: diameter, height: diameter)
      Image(systemName: phase.symbol)
        .font(.system(size: diameter * 0.42, weight: .bold))
        .foregroundColor(.white)
    }
  }
}

private struct TimerPill: View {
  let snap: Snap
  var compact: Bool = false

  var body: some View {
    HStack(spacing: 4) {
      if snap.expires.timeIntervalSinceNow > 1 {
        Text(timerInterval: Date()...snap.expires, countsDown: true)
          .monospacedDigit()
      } else {
        Text(snap.timerText)
          .monospacedDigit()
      }
    }
    .font(.system(size: compact ? 12 : 15, weight: .heavy, design: .rounded))
    .foregroundColor(.white)
    .padding(.horizontal, compact ? 8 : 10)
    .padding(.vertical, compact ? 4 : 6)
    .background(Brand.pillBg, in: Capsule())
  }
}

private struct IslandExpanded: View {
  let snap: Snap

  var body: some View {
    HStack(spacing: 12) {
      BrandBadge(phase: snap.phase, diameter: 44)
      VStack(alignment: .leading, spacing: 4) {
        Text(snap.phase.title)
          .font(.system(size: 14, weight: .heavy))
          .foregroundColor(.white)
        Text(snap.name)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.white.opacity(0.85))
          .lineLimit(1)
        Text(snap.phase.shortLabel)
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(snap.phase.accent)
      }
      Spacer(minLength: 0)
      TimerPill(snap: snap)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      LinearGradient(
        colors: [Brand.pillBg, snap.phase.accent.opacity(0.35)],
        startPoint: .leading,
        endPoint: .trailing
      ),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
    )
  }
}

private struct LockCard: View {
  let snap: Snap

  var body: some View {
    HStack(spacing: 14) {
      BrandBadge(phase: snap.phase, diameter: 40)
      VStack(alignment: .leading, spacing: 3) {
        Text("Intellisys · Check-in")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(snap.phase.accent)
        Text(snap.name)
          .font(.system(size: 16, weight: .heavy))
          .foregroundColor(.white)
          .lineLimit(1)
        Text(snap.phase.title)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.white.opacity(0.7))
      }
      Spacer()
      TimerPill(snap: snap)
    }
    .padding(16)
  }
}

// MARK: - Widget

struct CheckInLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      let snap = Snap(context)
      LockCard(snap: snap)
        .activityBackgroundTint(snap.phase.accent.opacity(0.25))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let snap = Snap(context)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          BrandBadge(phase: snap.phase, diameter: 36)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TimerPill(snap: snap, compact: true)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(snap.phase.shortLabel)
            .font(.system(size: 13, weight: .heavy))
            .foregroundColor(.white)
        }
        DynamicIslandExpandedRegion(.bottom) {
          IslandExpanded(snap: snap)
        }
      } compactLeading: {
        BrandBadge(phase: snap.phase, diameter: 24)
      } compactTrailing: {
        TimerPill(snap: snap, compact: true)
      } minimal: {
        BrandBadge(phase: snap.phase, diameter: 22)
      }
      .keylineTint(snap.phase.accent)
      .widgetURL(URL(string: "dreamkeys://check-in")!)
    }
  }
}
