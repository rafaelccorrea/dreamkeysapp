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

private let kAppGroupId = "group.com.dreamkeys.corretor"
private let kActivityName = "checkin"
private let sharedDefaults = UserDefaults(suiteName: kAppGroupId)

private enum IslandKey {
  static let userName = "island_userName"
  static let statusPhase = "island_statusPhase"
  static let expiresAtEpoch = "island_expiresAtEpoch"
  static let checkedInAtEpoch = "island_checkedInAtEpoch"
}

// Paleta refinada — verde vivo no ativo, vermelho forte ao expirar.
private enum Brand {
  /// Verde check-in (#22E870)
  static let ok = Color(red: 0.133, green: 0.910, blue: 0.439)
  static let okDeep = Color(red: 0.063, green: 0.725, blue: 0.333)
  static let okGlow = Color(red: 0.298, green: 1.0, blue: 0.573)

  static let warn = Color(red: 1.0, green: 0.784, blue: 0.071)   // #FFC812
  static let urgent = Color(red: 1.0, green: 0.549, blue: 0.118) // #FF8C1E
  static let danger = Color(red: 1.0, green: 0.231, blue: 0.188) // #FF3B30
  static let dangerDeep = Color(red: 0.780, green: 0.118, blue: 0.118)

  static let pillBg = Color(red: 0.11, green: 0.11, blue: 0.13)
  static let pillBgSoft = Color.white.opacity(0.10)
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

  var accentDeep: Color {
    switch self {
    case .active: return Brand.okDeep
    case .expiring: return Color(red: 0.85, green: 0.62, blue: 0.05)
    case .critical: return Color(red: 0.90, green: 0.42, blue: 0.08)
    case .expired: return Brand.dangerDeep
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

  var compactSymbol: String {
    switch self {
    case .active: return "checkmark"
    case .expiring: return "clock.fill"
    case .critical: return "bolt.fill"
    case .expired: return "xmark"
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
  let checkedIn: Date?
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

    let checkedMs = {
      if let s = ud?.string(forKey: IslandKey.checkedInAtEpoch), let d = Double(s), d > 0 { return d }
      return epoch("checkedInAtEpoch")
    }()

    expires = expiresMs > 0
      ? Date(timeIntervalSince1970: expiresMs / 1000.0)
      : Date().addingTimeInterval(2 * 3600)

    checkedIn = checkedMs > 0
      ? Date(timeIntervalSince1970: checkedMs / 1000.0)
      : nil

    var resolvedPhase = Phase.from({
      if let p = ud?.string(forKey: IslandKey.statusPhase), !p.isEmpty { return p }
      return str("statusPhase")
    }())

    let left = expires.timeIntervalSinceNow
    if left <= 1 {
      resolvedPhase = .expired
    } else if left < 5 * 60 {
      resolvedPhase = .critical
    } else if left < 15 * 60, resolvedPhase == .active {
      resolvedPhase = .expiring
    }
    phase = resolvedPhase
  }

  var isExpired: Bool {
    expires.timeIntervalSinceNow <= 1 || phase == .expired
  }

  var secondsLeft: Int {
    max(0, Int(expires.timeIntervalSinceNow))
  }

  var timerText: String {
    if isExpired { return "0:00" }
    let sec = secondsLeft
    let m = sec / 60
    let s = sec % 60
    if m >= 60 {
      let h = m / 60
      let rm = m % 60
      return rm > 0 ? String(format: "%dh%02dm", h, rm) : String(format: "%dh", h)
    }
    return String(format: "%d:%02d", m, s)
  }

  var compactTimerText: String {
    if isExpired { return "0:00" }
    let sec = secondsLeft
    let m = sec / 60
    let s = sec % 60
    if m >= 60 {
      let h = m / 60
      let rm = m % 60
      return String(format: "%dh%02d", h, rm)
    }
    return String(format: "%d:%02d", m, s)
  }

  /// Fração do tempo de check-in já consumida (0…1).
  var elapsedFraction: Double {
    guard let checked = checkedIn else { return 0 }
    let total = expires.timeIntervalSince(checked)
    guard total > 1 else { return isExpired ? 1 : 0 }
    let elapsed = Date().timeIntervalSince(checked)
    return min(1, max(0, elapsed / total))
  }
}

// MARK: - UI

private struct StatusOrb: View {
  let phase: Phase
  var diameter: CGFloat = 28
  var showRing: Bool = true

  var body: some View {
    ZStack {
      if showRing && phase != .expired {
        Circle()
          .stroke(
            LinearGradient(
              colors: [phase.accent, phase.accentDeep],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: diameter * 0.08
          )
          .frame(width: diameter + 4, height: diameter + 4)
      }

      if phase == .expired {
        Circle()
          .fill(
            LinearGradient(
              colors: [Brand.danger, Brand.dangerDeep],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: diameter, height: diameter)
      } else {
        Circle()
          .fill(
            LinearGradient(
              colors: [phase.accent, phase.accentDeep],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .frame(width: diameter, height: diameter)
          .shadow(color: phase.accent.opacity(0.45), radius: diameter * 0.12)
      }

      Image(systemName: phase.compactSymbol)
        .font(.system(size: diameter * 0.38, weight: .bold))
        .foregroundColor(.white)
    }
  }
}

private struct LiveCountdownText: View {
  let snap: Snap
  var fontSize: CGFloat = 15
  var weight: Font.Weight = .heavy

  var body: some View {
    Group {
      if snap.isExpired {
        Text("0:00")
          .monospacedDigit()
      } else {
        Text(timerInterval: Date()...snap.expires, countsDown: true)
          .monospacedDigit()
      }
    }
    .font(.system(size: fontSize, weight: weight, design: .rounded))
  }
}

/// Cronômetro ultra-compacto — só dígitos, sem cápsula (ilha recolhida).
private struct CompactIslandTimer: View {
  let snap: Snap

  private var color: Color {
    snap.isExpired ? Brand.danger : snap.phase.accent
  }

  var body: some View {
    Group {
      if snap.isExpired {
        Text("0:00")
          .monospacedDigit()
      } else if snap.secondsLeft >= 3600 {
        // >1h: "1h05" ocupa menos que "1:05:00"
        Text(snap.compactTimerText)
          .monospacedDigit()
      } else {
        Text(timerInterval: Date()...snap.expires, countsDown: true)
          .monospacedDigit()
      }
    }
    .font(.system(size: 10.5, weight: .bold, design: .rounded))
    .foregroundColor(color)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .fixedSize(horizontal: true, vertical: false)
  }
}

/// Ponto de status — mínimo horizontal.
private struct CompactIslandDot: View {
  let snap: Snap
  var size: CGFloat = 7

  var body: some View {
    Circle()
      .fill(
        snap.isExpired
          ? Brand.danger
          : snap.phase.accent
      )
      .frame(width: size, height: size)
      .overlay {
        if snap.isExpired {
          Image(systemName: "xmark")
            .font(.system(size: size * 0.55, weight: .black))
            .foregroundColor(.white)
        }
      }
  }
}

/// Leading recolhido — ícone da fase em círculo compacto (mais contexto que só o ponto).
private struct CompactLeadingRich: View {
  let snap: Snap

  var body: some View {
    ZStack {
      Circle()
        .fill(snap.phase.accent.opacity(snap.isExpired ? 0.35 : 0.22))
        .frame(width: 18, height: 18)
      Image(systemName: snap.phase.compactSymbol)
        .font(.system(size: 8, weight: .bold))
        .foregroundColor(snap.isExpired ? Brand.danger : snap.phase.accent)
    }
  }
}

/// Trailing recolhido — fase + cronômetro (sem repetir na expansão).
private struct CompactTrailingRich: View {
  let snap: Snap

  var body: some View {
    VStack(alignment: .trailing, spacing: 1) {
      Text(snap.phase.shortLabel)
        .font(.system(size: 7, weight: .heavy))
        .foregroundColor(snap.isExpired ? Brand.danger : snap.phase.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      CompactIslandTimer(snap: snap)
    }
    .fixedSize(horizontal: true, vertical: false)
  }
}

/// Faixa inferior da ilha expandida — metadados sem cronômetro (timer só no trailing).
private struct ExpandedBottomStrip: View {
  let snap: Snap

  var body: some View {
    VStack(spacing: 5) {
      HStack(spacing: 6) {
        if let checked = snap.checkedIn {
          HStack(spacing: 3) {
            Image(systemName: "arrow.right.circle.fill")
              .font(.system(size: 9, weight: .semibold))
              .foregroundColor(snap.phase.accent.opacity(0.9))
            Text(checked, style: .time)
              .font(.system(size: 10, weight: .semibold, design: .rounded))
              .foregroundColor(.white.opacity(0.72))
          }
        }

        if snap.checkedIn != nil {
          Text("·")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(0.28))
        }

        if snap.isExpired {
          Text("Renove no app")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(Brand.danger)
        } else {
          HStack(spacing: 3) {
            Image(systemName: "hourglass.bottomhalf.filled")
              .font(.system(size: 8, weight: .semibold))
              .foregroundColor(.white.opacity(0.45))
            Text("Até \(snap.expires, style: .time)")
              .font(.system(size: 10, weight: .semibold, design: .rounded))
              .foregroundColor(.white.opacity(0.58))
          }
        }

        Spacer(minLength: 0)
      }

      if snap.checkedIn != nil && !snap.isExpired {
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(height: 3)
          Capsule()
            .fill(
              LinearGradient(
                colors: [snap.phase.accent, snap.phase.accentDeep],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .frame(maxWidth: .infinity)
            .frame(height: 3)
            .scaleEffect(x: max(0.04, snap.elapsedFraction), y: 1, anchor: .leading)
        }
        .frame(height: 3)
      }
    }
    .padding(.horizontal, 10)
    .padding(.top, 2)
    .padding(.bottom, 2)
  }
}

/// Cápsula do cronômetro — expandido / lock screen (não usar recolhido).
private struct TimerCapsule: View {
  let snap: Snap
  var compact: Bool = false

  private var fg: Color {
    snap.isExpired ? .white : (snap.phase == .active ? Color.black.opacity(0.88) : .white)
  }

  private var bg: some ShapeStyle {
    if snap.isExpired {
      return AnyShapeStyle(
        LinearGradient(
          colors: [Brand.danger, Brand.dangerDeep],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
    if snap.phase == .active {
      return AnyShapeStyle(
        LinearGradient(
          colors: [Brand.okGlow, Brand.ok],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
    }
    return AnyShapeStyle(
      LinearGradient(
        colors: [snap.phase.accent, snap.phase.accentDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    )
  }

  var body: some View {
    HStack(spacing: compact ? 4 : 6) {
      if !snap.isExpired && snap.phase == .active {
        Circle()
          .fill(Color.black.opacity(0.22))
          .frame(width: compact ? 4 : 5, height: compact ? 4 : 5)
      }

      LiveCountdownText(
        snap: snap,
        fontSize: compact ? 12 : 15,
        weight: .heavy
      )
      .foregroundColor(fg)

      if snap.isExpired {
        Image(systemName: "exclamationmark")
          .font(.system(size: compact ? 8 : 9, weight: .black))
          .foregroundColor(.white.opacity(0.95))
      }
    }
    .padding(.horizontal, compact ? 9 : 12)
    .padding(.vertical, compact ? 5 : 7)
    .background(bg, in: Capsule())
    .overlay {
      if snap.isExpired {
        Capsule()
          .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
      }
    }
  }
}

/// Modo minimal — ponto + tempo restante (máximo de info no espaço mínimo).
private struct MinimalIsland: View {
  let snap: Snap

  var body: some View {
    HStack(spacing: 3) {
      CompactIslandDot(snap: snap, size: 6)
      CompactIslandTimer(snap: snap)
    }
  }
}

private struct LockCard: View {
  let snap: Snap

  var body: some View {
    HStack(spacing: 14) {
      StatusOrb(phase: snap.phase, diameter: 42, showRing: true)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text("Intellisys")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(snap.phase.accent)
          Capsule()
            .fill(snap.phase.accent.opacity(0.25))
            .frame(width: 4, height: 4)
          Text(snap.phase.shortLabel)
            .font(.system(size: 10, weight: .heavy))
            .foregroundColor(snap.phase.accent)
        }
        Text(snap.name)
          .font(.system(size: 16, weight: .heavy))
          .foregroundColor(.white)
          .lineLimit(1)
        Text(snap.phase.title)
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.white.opacity(0.68))
      }

      Spacer(minLength: 8)

      TimerCapsule(snap: snap)
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
        .activityBackgroundTint(snap.phase.accentDeep.opacity(0.32))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let snap = Snap(context)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          StatusOrb(phase: snap.phase, diameter: 30, showRing: true)
            .padding(.leading, 2)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TimerCapsule(snap: snap, compact: true)
            .padding(.trailing, 2)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            HStack(spacing: 4) {
              Text("Intellisys")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(snap.phase.accent.opacity(0.95))
              Text(snap.phase.shortLabel.uppercased())
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.white.opacity(0.42))
                .tracking(0.4)
            }
            Text(snap.name)
              .font(.system(size: 13, weight: .heavy))
              .foregroundColor(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.85)
            Text(snap.phase.title)
              .font(.system(size: 10, weight: .medium))
              .foregroundColor(.white.opacity(0.55))
              .lineLimit(1)
          }
          .frame(maxWidth: .infinity)
        }
        DynamicIslandExpandedRegion(.bottom) {
          ExpandedBottomStrip(snap: snap)
        }
      } compactLeading: {
        CompactLeadingRich(snap: snap)
      } compactTrailing: {
        CompactTrailingRich(snap: snap)
      } minimal: {
        MinimalIsland(snap: snap)
      }
      .keylineTint(snap.isExpired ? Brand.danger : snap.phase.accent)
      .widgetURL(URL(string: "dreamkeys://check-in")!)
    }
  }
}
