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

// Gramática das ilhas de referência (iFood/Uber/placar): IDENTIDADE DE MARCA
// sempre visível + dados em BRANCO + cor da fase só como acento pequeno
// (dot, anel, barra de progresso, eyebrow). Timer nunca é colorido — a única
// exceção é o vermelho de alerta quando expira.
private enum Brand {
  /// Vermelho institucional Intellisys (≈ #D32F2F) — só no roundel da marca.
  static let red = Color(red: 0.827, green: 0.184, blue: 0.184)
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

  /// Fração do tempo de check-in já consumida (0…1).
  var elapsedFraction: Double {
    guard let checked = checkedIn else { return 0 }
    let total = expires.timeIntervalSince(checked)
    guard total > 1 else { return isExpired ? 1 : 0 }
    let elapsed = Date().timeIntervalSince(checked)
    return min(1, max(0, elapsed / total))
  }

  /// Cor de acento da fase (vermelho de alerta quando expirado).
  var accent: Color {
    isExpired ? Brand.danger : phase.accent
  }
}

// MARK: - UI

/// Monograma Intellisys — roundel vermelho da marca com "i" tipográfico
/// branco. É a identidade fixa da ilha (como o logo do iFood/Uber): nunca
/// muda de cor com a fase.
private struct BrandMark: View {
  var size: CGFloat = 17

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        .fill(Brand.red)
      Text("i")
        .font(.system(size: size * 0.68, weight: .black, design: .rounded))
        .italic()
        .foregroundColor(.white)
        .offset(x: -size * 0.02, y: -size * 0.03)
    }
    .frame(width: size, height: size)
  }
}

/// Dot 6px — a menor unidade de cor da fase (acompanha o timer branco).
private struct PhaseDot: View {
  let snap: Snap
  var size: CGFloat = 6

  var body: some View {
    Circle()
      .fill(snap.accent)
      .frame(width: size, height: size)
  }
}

/// Minimal: BrandMark com anel fino de progresso da fase ao redor.
private struct BrandRing: View {
  let snap: Snap
  var size: CGFloat = 14
  var lineWidth: CGFloat = 2

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
            snap.accent,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
        BrandMark(size: size)
      }
      .frame(width: size + 6, height: size + 6)
    }
  }
}

/// Barra de progresso fina (estilo player do Spotify): track discreto,
/// preenchimento na cor da fase, largura total, 3px.
private struct PhaseProgressBar: View {
  let snap: Snap
  var height: CGFloat = 3

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { _ in
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.white.opacity(0.12))
          Capsule()
            .fill(snap.accent)
            .frame(
              width: max(
                height,
                geo.size.width * (snap.isExpired ? 1 : snap.elapsedFraction)
              )
            )
        }
      }
      .frame(height: height)
    }
  }
}

/// Dígitos do cronômetro — sempre BRANCOS (vermelho só quando expira).
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
    .foregroundColor(snap.isExpired ? Brand.danger : .white)
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
  }
}

/// Trailing compacto: dot da fase + dígitos brancos (o verde vira só o dot).
private struct CompactTimer: View {
  let snap: Snap
  var fontSize: CGFloat = 12

  var body: some View {
    HStack(spacing: 5) {
      PhaseDot(snap: snap)
      Group {
        if snap.isExpired {
          Text("0:00")
            .monospacedDigit()
        } else if snap.secondsLeft >= 3600 {
          // >1h: "1h05" ocupa menos que "1:05:00"
          TimelineView(.periodic(from: .now, by: 30)) { _ in
            Text(snap.compactTimerText)
              .monospacedDigit()
          }
        } else {
          Text(timerInterval: Date()...snap.expires, countsDown: true)
            .monospacedDigit()
        }
      }
      .font(.system(size: fontSize, weight: .bold, design: .rounded))
      .foregroundColor(snap.isExpired ? Brand.danger : .white)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .fixedSize(horizontal: true, vertical: false)
    }
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

/// Status curto ao lado da barra: "Ativo até 15:30" / "Expirado — renove".
private struct StatusLine: View {
  let snap: Snap
  var fontSize: CGFloat = 10

  var body: some View {
    Group {
      if snap.isExpired {
        Text("Expirado — renove")
          .foregroundColor(Brand.danger)
      } else {
        (Text("Ativo até ") + Text(snap.expires, style: .time))
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
    VStack(spacing: 12) {
      HStack(spacing: 14) {
        BrandMark(size: 40)

        VStack(alignment: .leading, spacing: 3) {
          Text("CHECK-IN · \(snap.phase.shortLabel.uppercased())")
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(1.4)
            .foregroundColor(snap.accent)
            .lineLimit(1)
          Text(snap.companyDisplayName)
            .font(.system(size: 16, weight: .black))
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
          EntryWindowLine(snap: snap)
        }

        Spacer(minLength: 8)

        LiveCountdownText(snap: snap, fontSize: 24)
      }

      PhaseProgressBar(snap: snap)
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
          BrandMark(size: 30)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 4) {
            PhaseDot(snap: snap)
            LiveCountdownText(snap: snap, fontSize: 20, islandCompact: true)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
          .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 2) {
            Text("CHECK-IN")
              .font(.system(size: 8.5, weight: .heavy))
              .tracking(1.6)
              .foregroundColor(snap.accent)
              .lineLimit(1)
            Text(snap.companyDisplayName)
              .font(.system(size: 14, weight: .heavy))
              .foregroundColor(.white)
              .lineLimit(1)
              .minimumScaleFactor(0.75)
            EntryWindowLine(snap: snap, fontSize: 10)
          }
          .frame(maxWidth: .infinity)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 7) {
            PhaseProgressBar(snap: snap)
            HStack {
              StatusLine(snap: snap)
              Spacer(minLength: 8)
              CheckoutPill(snap: snap)
            }
          }
          .padding(.horizontal, 6)
          .padding(.top, 4)
        }
      } compactLeading: {
        BrandMark(size: 17)
      } compactTrailing: {
        CompactTimer(snap: snap)
      } minimal: {
        BrandRing(snap: snap, size: 14, lineWidth: 2)
      }
      .keylineTint(snap.accent)
      .widgetURL(URL(string: "dreamkeys://check-in")!)
    }
  }
}
