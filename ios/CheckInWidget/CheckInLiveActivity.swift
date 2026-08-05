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
  static let companyName = "island_companyName"
  static let statusPhase = "island_statusPhase"
  static let expiresAtEpoch = "island_expiresAtEpoch"
  static let checkedInAtEpoch = "island_checkedInAtEpoch"
}

private let kCheckoutDeepLink = URL(string: "dreamkeys://check-in/checkout")!

// Paleta sóbria — cores do sistema iOS, UMA por fase, aplicada só em
// acentos (dot, anel, timer, keyline). Nada de gradiente/glow: superfície
// é o material escuro da própria ilha/lock screen.
private enum Brand {
  static let ok = Color(red: 0.188, green: 0.820, blue: 0.345)     // #30D158
  static let warn = Color(red: 1.0, green: 0.839, blue: 0.039)     // #FFD60A
  static let urgent = Color(red: 1.0, green: 0.624, blue: 0.039)   // #FF9F0A
  static let danger = Color(red: 1.0, green: 0.271, blue: 0.227)   // #FF453A
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
    case .active: return "Ativo"
    case .expiring: return "Expira"
    case .critical: return "Urgente"
    case .expired: return "Expirou"
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
  let companyName: String
  let expires: Date
  let checkedIn: Date?
  let phase: Phase

  init(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) {
    let ud = sharedDefaults
    let pluginId = uuid5(namespace: kNamespaceDNS, name: kActivityName)

    func str(_ field: String) -> String? {
      if let ud = ud {
        if field == "userName", let v = ud.string(forKey: IslandKey.userName), !v.isEmpty { return v }
        if field == "companyName", let v = ud.string(forKey: IslandKey.companyName), !v.isEmpty { return v }
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

    companyName = {
      if let c = ud?.string(forKey: IslandKey.companyName), !c.isEmpty { return c }
      return str("companyName") ?? ""
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

  var companyDisplayName: String {
    let trimmed = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Imobiliária" : trimmed
  }

  /// Legenda compacta: empresa quando check-in ok; alerta nas demais fases.
  var compactContextLabel: String {
    switch phase {
    case .active:
      return companyDisplayName
    case .expiring, .critical, .expired:
      return phase.shortLabel
    }
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

/// Anel de progresso do tempo — a cor da fase esvazia conforme a janela do
/// check-in é consumida; ícone da fase no centro (opcional). Substitui o
/// antigo orb com gradiente+glow: mesmo dado, metade do peso visual.
private struct PhaseRing: View {
  let snap: Snap
  var diameter: CGFloat = 28
  var lineWidth: CGFloat = 2.5
  var showIcon: Bool = true

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { _ in
      ZStack {
        Circle()
          .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
        Circle()
          .trim(
            from: 0,
            to: snap.isExpired ? 1 : max(0.03, 1 - snap.elapsedFraction)
          )
          .stroke(
            snap.phase.accent,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
        if showIcon {
          Image(systemName: snap.phase.compactSymbol)
            .font(.system(size: diameter * 0.34, weight: .bold))
            .foregroundColor(snap.phase.accent)
        }
      }
      .frame(width: diameter, height: diameter)
    }
  }
}

private struct LiveCountdownText: View {
  let snap: Snap
  var fontSize: CGFloat = 15
  var weight: Font.Weight = .heavy
  /// Em slots estreitos da Ilha (trailing expandido), evita `timerInterval` em HH:MM:SS.
  var islandCompact: Bool = false

  var body: some View {
    Group {
      if snap.isExpired {
        Text("0:00")
          .monospacedDigit()
      } else if islandCompact || snap.secondsLeft >= 3600 {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
          Text(snap.timerText)
            .monospacedDigit()
        }
      } else {
        Text(timerInterval: Date()...snap.expires, countsDown: true)
          .monospacedDigit()
      }
    }
    .font(.system(size: fontSize, weight: weight, design: .rounded))
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
  }
}

/// Cronômetro compacto — só dígitos na cor da fase (ilha recolhida).
private struct CompactIslandTimer: View {
  let snap: Snap
  var fontSize: CGFloat = 12

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
    .font(.system(size: fontSize, weight: .bold, design: .rounded))
    .foregroundColor(color)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .fixedSize(horizontal: true, vertical: false)
  }
}

/// Timer protagonista — dígitos grandes na cor da fase, sem cápsula.
/// (A cápsula gradiente anterior competia com todo o resto da tela.)
private struct HeroTimer: View {
  let snap: Snap
  var fontSize: CGFloat = 24
  var islandCompact: Bool = false

  var body: some View {
    LiveCountdownText(
      snap: snap,
      fontSize: fontSize,
      weight: .heavy,
      islandCompact: islandCompact
    )
    .foregroundColor(snap.isExpired ? Brand.danger : snap.phase.accent)
  }
}

/// Linha informativa: entrada · até HH:mm (ou aviso de renovação).
/// Cada palavra carrega dado real — nada de rótulo decorativo.
private struct EntryWindowLine: View {
  let snap: Snap
  var fontSize: CGFloat = 11

  var body: some View {
    HStack(spacing: 5) {
      if let checked = snap.checkedIn {
        (Text("Entrada ") + Text(checked, style: .time))
          .foregroundColor(.white.opacity(0.55))
        Text("·")
          .foregroundColor(.white.opacity(0.25))
      }
      if snap.isExpired {
        Text("Renove no app")
          .foregroundColor(Brand.danger)
      } else {
        (Text("Até ") + Text(snap.expires, style: .time))
          .foregroundColor(.white.opacity(0.55))
      }
    }
    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
    .lineLimit(1)
  }
}

/// Encerra check-in (deep link → app faz checkout). Ghost discreto.
private struct CheckoutPill: View {
  let snap: Snap

  var body: some View {
    Link(destination: kCheckoutDeepLink) {
      HStack(spacing: 4) {
        Image(systemName: "rectangle.portrait.and.arrow.right")
          .font(.system(size: 9, weight: .bold))
        Text("Sair")
          .font(.system(size: 10.5, weight: .heavy))
      }
      .foregroundColor(.white.opacity(0.85))
      .padding(.horizontal, 11)
      .padding(.vertical, 5)
      .overlay(
        Capsule()
          .stroke(Color.white.opacity(0.18), lineWidth: 1)
      )
    }
  }
}

private struct LockCard: View {
  let snap: Snap

  var body: some View {
    HStack(spacing: 14) {
      PhaseRing(snap: snap, diameter: 40, lineWidth: 3)

      VStack(alignment: .leading, spacing: 3) {
        Text("CHECK-IN · \(snap.phase.shortLabel.uppercased())")
          .font(.system(size: 9.5, weight: .heavy))
          .tracking(1.4)
          .foregroundColor(snap.phase.accent)
          .lineLimit(1)
        Text(snap.companyDisplayName)
          .font(.system(size: 16, weight: .heavy))
          .foregroundColor(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        EntryWindowLine(snap: snap)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 6) {
        HeroTimer(snap: snap, fontSize: 24)
        CheckoutPill(snap: snap)
      }
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
        .activityBackgroundTint(Color.black.opacity(0.55))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let snap = Snap(context)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          PhaseRing(snap: snap, diameter: 28, lineWidth: 2.5)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          HeroTimer(snap: snap, fontSize: 16, islandCompact: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text("CHECK-IN · \(snap.phase.shortLabel.uppercased())")
              .font(.system(size: 8.5, weight: .heavy))
              .tracking(1.2)
              .foregroundColor(snap.phase.accent)
              .lineLimit(1)
            Text(snap.companyDisplayName)
              .font(.system(size: 13, weight: .heavy))
              .foregroundColor(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
          }
          .frame(maxWidth: .infinity)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            EntryWindowLine(snap: snap, fontSize: 10)
            Spacer(minLength: 8)
            CheckoutPill(snap: snap)
          }
          .padding(.horizontal, 6)
          .padding(.top, 2)
        }
      } compactLeading: {
        PhaseRing(snap: snap, diameter: 15, lineWidth: 2, showIcon: false)
      } compactTrailing: {
        CompactIslandTimer(snap: snap)
      } minimal: {
        PhaseRing(snap: snap, diameter: 14, lineWidth: 2, showIcon: false)
      }
      .keylineTint(snap.isExpired ? Brand.danger : snap.phase.accent)
      .widgetURL(URL(string: "dreamkeys://check-in")!)
    }
  }
}
