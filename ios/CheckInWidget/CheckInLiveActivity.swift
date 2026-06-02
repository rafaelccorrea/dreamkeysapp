import ActivityKit
import WidgetKit
import SwiftUI

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  public struct ContentState: Codable, Hashable {}
  var id = UUID()
}

let sharedDefault = UserDefaults(suiteName: "group.com.dreamkeys.corretor")!

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    "\(id)_\(key)"
  }
}

// MARK: - Design tokens

private enum CK {
  static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)
  static let emeraldGlow = Color(red: 0.298, green: 0.949, blue: 0.769)
  static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)
  static let orange = Color(red: 0.976, green: 0.451, blue: 0.086)
  static let red = Color(red: 0.937, green: 0.267, blue: 0.267)
  static let violet = Color(red: 0.388, green: 0.400, blue: 0.945)

  /// Texto na ilha (fundo OLED preto do sistema).
  static let islandPrimary = Color.white
  static let islandSecondary = Color.white.opacity(0.62)
  static let islandTertiary = Color.white.opacity(0.42)
}

private enum CheckInPhase {
  case active, expiring, critical, expired

  var accent: Color {
    switch self {
    case .active: return CK.emerald
    case .expiring: return CK.amber
    case .critical: return CK.orange
    case .expired: return CK.red
    }
  }

  var glow: Color {
    switch self {
    case .active: return CK.emeraldGlow
    case .expiring: return CK.amber
    case .critical: return CK.orange
    case .expired: return CK.red
    }
  }

  var title: String {
    switch self {
    case .active: return "Na imobiliária"
    case .expiring: return "Expira em breve"
    case .critical: return "Quase no fim"
    case .expired: return "Expirado"
    }
  }

  var shortTitle: String {
    switch self {
    case .active: return "Ativo"
    case .expiring: return "Em breve"
    case .critical: return "Urgente"
    case .expired: return "Expirado"
    }
  }

  var symbol: String {
    switch self {
    case .active: return "building.2.fill"
    case .expiring: return "clock.fill"
    case .critical: return "bolt.fill"
    case .expired: return "xmark.circle.fill"
    }
  }
}

// MARK: - Data

private func laEpochMs(_ ctx: ActivityViewContext<LiveActivitiesAppAttributes>, key: String) -> Double {
  let k = ctx.attributes.prefixedKey(key)
  if let n = sharedDefault.object(forKey: k) as? NSNumber { return n.doubleValue }
  if let s = sharedDefault.string(forKey: k), let v = Double(s) { return v }
  return 0
}

private func laString(_ ctx: ActivityViewContext<LiveActivitiesAppAttributes>, key: String) -> String {
  sharedDefault.string(forKey: ctx.attributes.prefixedKey(key)) ?? ""
}

private struct CheckInSnapshot {
  let userName: String
  let checkedIn: Date
  let expires: Date
  let phase: CheckInPhase

  init(context: ActivityViewContext<LiveActivitiesAppAttributes>) {
    let raw = laString(context, key: "userName").trimmingCharacters(in: .whitespacesAndNewlines)
    userName = raw.isEmpty ? "Corretor" : raw

    let checkedMs = laEpochMs(context, key: "checkedInAtEpoch")
    let expiresMs = laEpochMs(context, key: "expiresAtEpoch")
    let now = Date()

    checkedIn = checkedMs > 0
      ? Date(timeIntervalSince1970: checkedMs / 1000.0)
      : now
    expires = expiresMs > 0
      ? Date(timeIntervalSince1970: expiresMs / 1000.0)
      : now.addingTimeInterval(3600)

    let left = expires.timeIntervalSince(now)
    if left <= 1 { phase = .expired }
    else if left < 5 * 60 { phase = .critical }
    else if left < 15 * 60 { phase = .expiring }
    else { phase = .active }
  }

  var remainingRatio: Double {
    let total = expires.timeIntervalSince(checkedIn)
    guard total > 1 else { return 0 }
    let left = max(0, expires.timeIntervalSinceNow)
    return min(1, max(0, left / total))
  }

  var elapsedRatio: Double { 1 - remainingRatio }

  var entryTime: String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "HH:mm"
    return f.string(from: checkedIn)
  }

  var expiryLabel: String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "pt_BR")
    f.dateFormat = "HH:mm"
    return f.string(from: expires)
  }
}

// MARK: - Primitives

private struct IslandTimer: View {
  let expires: Date
  let phase: CheckInPhase
  var font: Font = .system(size: 12, weight: .semibold, design: .rounded)
  var gradient: Bool = false
  var solidColor: Color? = nil

  var body: some View {
    Group {
      if expires.timeIntervalSinceNow > 1 {
        Text(timerInterval: Date()...expires, countsDown: true)
      } else {
        Text("0:00")
      }
    }
    .font(font)
    .monospacedDigit()
    .foregroundStyle(timerStyle)
  }

  private var timerStyle: AnyShapeStyle {
    if let solidColor { return AnyShapeStyle(solidColor) }
    if gradient { return AnyShapeStyle(timerGradient) }
    return AnyShapeStyle(phase.accent)
  }

  private var timerGradient: LinearGradient {
    LinearGradient(
      colors: [.white, phase.glow],
      startPoint: .leading,
      endPoint: .trailing
    )
  }
}

/// Ícone com halo — assinatura visual compacta (estilo apps nativos).
private struct BrandGlyph: View {
  let phase: CheckInPhase
  var diameter: CGFloat = 28

  var body: some View {
    ZStack {
      Circle()
        .fill(
          RadialGradient(
            colors: [phase.glow.opacity(0.55), phase.accent.opacity(0.08)],
            center: .center,
            startRadius: 0,
            endRadius: diameter * 0.55
          )
        )
        .frame(width: diameter, height: diameter)

      Circle()
        .strokeBorder(
          LinearGradient(
            colors: [phase.glow.opacity(0.9), phase.accent.opacity(0.35)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          ),
          lineWidth: 1.5
        )
        .frame(width: diameter, height: diameter)

      Image(systemName: phase.symbol)
        .font(.system(size: diameter * 0.38, weight: .semibold))
        .foregroundStyle(
          LinearGradient(
            colors: [.white, phase.glow],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .symbolRenderingMode(.hierarchical)
    }
  }
}

/// Anel de progresso (restante do check-in).
private struct RemainingRing: View {
  let ratio: Double
  let phase: CheckInPhase
  var lineWidth: CGFloat = 3.5
  var size: CGFloat = 40

  var body: some View {
    ZStack {
      Circle()
        .stroke(CK.islandTertiary, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: ratio)
        .stroke(
          AngularGradient(
            colors: [phase.accent, phase.glow, phase.accent],
            center: .center
          ),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
      Text("\(Int(ratio * 100))")
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(CK.islandSecondary)
    }
    .frame(width: size, height: size)
  }
}

private struct SlimProgress: View {
  let progress: Double
  let phase: CheckInPhase

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(CK.islandTertiary)
        Capsule()
          .fill(
            LinearGradient(
              colors: [phase.accent, phase.glow],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: max(6, geo.size.width * progress))
      }
    }
    .frame(height: 4)
  }
}

// MARK: - Dynamic Island regions

private struct IslandExpandedLeading: View {
  let snap: CheckInSnapshot

  var body: some View {
    VStack(spacing: 6) {
      BrandGlyph(phase: snap.phase, diameter: 36)
      Text(snap.phase.shortTitle)
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(snap.phase.accent)
        .textCase(.uppercase)
        .tracking(0.4)
    }
    .frame(maxHeight: .infinity, alignment: .center)
  }
}

private struct IslandExpandedCenter: View {
  let snap: CheckInSnapshot

  var body: some View {
    VStack(spacing: 4) {
      Text(snap.phase.title)
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(CK.islandPrimary)
        .lineLimit(1)

      IslandTimer(
        expires: snap.expires,
        phase: snap.phase,
        font: .system(size: 32, weight: .bold, design: .rounded),
        gradient: true
      )

      Text(snap.userName)
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(CK.islandSecondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .multilineTextAlignment(.center)
  }
}

private struct IslandExpandedTrailing: View {
  let snap: CheckInSnapshot

  var body: some View {
    VStack(spacing: 5) {
      RemainingRing(ratio: snap.remainingRatio, phase: snap.phase, size: 44)
      Text("restante")
        .font(.system(size: 8, weight: .medium, design: .rounded))
        .foregroundStyle(CK.islandTertiary)
        .textCase(.uppercase)
        .tracking(0.3)
    }
    .frame(maxHeight: .infinity, alignment: .center)
  }
}

private struct IslandExpandedBottom: View {
  let snap: CheckInSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SlimProgress(progress: snap.remainingRatio, phase: snap.phase)

      HStack(alignment: .firstTextBaseline) {
        Label {
          Text("Entrada \(snap.entryTime)")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(CK.islandSecondary)
        } icon: {
          Image(systemName: "arrow.right.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(snap.phase.accent)
        }

        Spacer(minLength: 8)

        Text("até \(snap.expiryLabel)")
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .foregroundStyle(CK.islandTertiary)

        Text("·")
          .foregroundStyle(CK.islandTertiary)

        Text("Intellisys")
          .font(.system(size: 9, weight: .bold, design: .rounded))
          .foregroundStyle(CK.violet.opacity(0.85))
      }
    }
    .padding(.horizontal, 2)
    .padding(.top, 2)
  }
}

private struct IslandCompactLeading: View {
  let snap: CheckInSnapshot

  var body: some View {
    BrandGlyph(phase: snap.phase, diameter: 22)
  }
}

private struct IslandCompactTrailing: View {
  let snap: CheckInSnapshot

  var body: some View {
    IslandTimer(
      expires: snap.expires,
      phase: snap.phase,
      font: .system(size: 13, weight: .bold, design: .rounded)
    )
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(snap.phase.accent.opacity(0.18))
          .overlay(
            Capsule()
              .strokeBorder(snap.phase.accent.opacity(0.35), lineWidth: 0.5)
          )
      )
  }
}

private struct IslandMinimal: View {
  let snap: CheckInSnapshot

  var body: some View {
    ZStack {
      Circle()
        .fill(snap.phase.accent)
        .frame(width: 18, height: 18)
      Image(systemName: "checkmark")
        .font(.system(size: 9, weight: .black))
        .foregroundStyle(.white)
    }
  }
}

// MARK: - Lock Screen (banner premium)

private struct LockScreenBanner: View {
  let snap: CheckInSnapshot

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      BrandGlyph(phase: snap.phase, diameter: 48)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text(snap.phase.title.uppercased())
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(snap.phase.glow)

          Circle()
            .fill(snap.phase.accent)
            .frame(width: 5, height: 5)
        }

        Text(snap.userName)
          .font(.system(.headline, design: .rounded))
          .fontWeight(.bold)
          .foregroundStyle(.white)
          .lineLimit(1)

        Text("Entrada às \(snap.entryTime) · válido até \(snap.expiryLabel)")
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.65))
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      VStack(alignment: .trailing, spacing: 2) {
        IslandTimer(
          expires: snap.expires,
          phase: snap.phase,
          font: .system(size: 22, weight: .heavy, design: .rounded),
          solidColor: .white
        )

        Text("restante")
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.5))
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}

// MARK: - Widget

struct CheckInLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      let snap = CheckInSnapshot(context: context)

      LockScreenBanner(snap: snap)
        .activityBackgroundTint(snap.phase.accent.opacity(0.38))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let snap = CheckInSnapshot(context: context)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          IslandExpandedLeading(snap: snap)
        }
        DynamicIslandExpandedRegion(.center) {
          IslandExpandedCenter(snap: snap)
        }
        DynamicIslandExpandedRegion(.trailing) {
          IslandExpandedTrailing(snap: snap)
        }
        DynamicIslandExpandedRegion(.bottom) {
          IslandExpandedBottom(snap: snap)
        }
      } compactLeading: {
        IslandCompactLeading(snap: snap)
      } compactTrailing: {
        IslandCompactTrailing(snap: snap)
      } minimal: {
        IslandMinimal(snap: snap)
      }
      .keylineTint(snap.phase.glow)
    }
  }
}
