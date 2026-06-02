import ActivityKit
import CryptoKit
import SwiftUI
import WidgetKit

// ⚠️ DEVE ser idêntico ao `LiveActivitiesAppAttributes` do plugin `live_activities`
// (incluindo ContentState com `appGroupId`). Schema diferente = ilha vazia.
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

// MARK: - App Group + leitura de dados (UserDefaults)

private let kDefaultAppGroup = "group.com.dreamkeys.corretor"
private let kCheckInActivityName = "checkin"

private func appGroupDefaults(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) -> UserDefaults? {
  let groupId = context.state.appGroupId.isEmpty ? kDefaultAppGroup : context.state.appGroupId
  return UserDefaults(suiteName: groupId)
}

/// Mesmo algoritmo do plugin (`uuid5`) para achar chaves se `attributes.id` falhar.
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

private func prefixedKeys(for id: UUID, field: String) -> [String] {
  let base = "\(id.uuidString)_\(field)"
  let legacy = "\(id)_\(field)"
  let pluginId = uuid5(namespace: kNamespaceDNS, name: kCheckInActivityName)
  return [
    base,
    legacy,
    "\(pluginId.uuidString)_\(field)",
    "\(pluginId)_\(field)",
  ]
}

private func readString(
  _ context: ActivityViewContext<LiveActivitiesAppAttributes>,
  field: String
) -> String? {
  guard let ud = appGroupDefaults(context) else { return nil }
  let primary = context.attributes.prefixedKey(field)
  if let s = ud.string(forKey: primary), !s.trimmingCharacters(in: .whitespaces).isEmpty {
    return s.trimmingCharacters(in: .whitespaces)
  }
  for key in prefixedKeys(for: context.attributes.id, field: field) {
    if let s = ud.string(forKey: key), !s.trimmingCharacters(in: .whitespaces).isEmpty {
      return s.trimmingCharacters(in: .whitespaces)
    }
  }
  let suffix = "_\(field)"
  for (key, value) in ud.dictionaryRepresentation() {
    guard key.hasSuffix(suffix) else { continue }
    if let s = value as? String, !s.trimmingCharacters(in: .whitespaces).isEmpty {
      return s.trimmingCharacters(in: .whitespaces)
    }
  }
  return nil
}

private func readEpochMs(
  _ context: ActivityViewContext<LiveActivitiesAppAttributes>,
  field: String
) -> Double {
  guard let ud = appGroupDefaults(context) else { return 0 }
  let primary = context.attributes.prefixedKey(field)
  if let n = ud.object(forKey: primary) as? NSNumber { return n.doubleValue }
  if let s = ud.string(forKey: primary), let v = Double(s) { return v }
  for key in prefixedKeys(for: context.attributes.id, field: field) {
    if let n = ud.object(forKey: key) as? NSNumber { return n.doubleValue }
    if let s = ud.string(forKey: key), let v = Double(s) { return v }
  }
  let suffix = "_\(field)"
  for (key, value) in ud.dictionaryRepresentation() {
    guard key.hasSuffix(suffix) else { continue }
    if let n = value as? NSNumber { return n.doubleValue }
    if let s = value as? String, let v = Double(s) { return v }
  }
  return 0
}

// MARK: - Modelo visual

private enum CK {
  static let green = Color(red: 0.063, green: 0.725, blue: 0.506)
  static let amber = Color(red: 0.961, green: 0.620, blue: 0.043)
  static let orange = Color(red: 0.976, green: 0.451, blue: 0.086)
  static let red = Color(red: 0.937, green: 0.267, blue: 0.267)
}

private enum Phase {
  case active, expiring, critical, expired

  var color: Color {
    switch self {
    case .active: return CK.green
    case .expiring: return CK.amber
    case .critical: return CK.orange
    case .expired: return CK.red
    }
  }

  var label: String {
    switch self {
    case .active: return "Na imobiliária"
    case .expiring: return "Expira em breve"
    case .critical: return "Urgente"
    case .expired: return "Expirado"
    }
  }

  var symbol: String {
    switch self {
    case .active: return "building.2.fill"
    case .expiring: return "clock.fill"
    case .critical: return "exclamationmark.triangle.fill"
    case .expired: return "xmark.circle.fill"
    }
  }
}

private struct Snap {
  let name: String
  let checkedIn: Date
  let expires: Date
  let phase: Phase
  let hasRealData: Bool

  init(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) {
    let rawName = readString(context, field: "userName")
    name = rawName ?? "Check-in ativo"

    let checkedMs = readEpochMs(context, field: "checkedInAtEpoch")
    let expiresMs = readEpochMs(context, field: "expiresAtEpoch")
    let now = Date()

    hasRealData = expiresMs > 0 || checkedMs > 0 || rawName != nil

    checkedIn = checkedMs > 0
      ? Date(timeIntervalSince1970: checkedMs / 1000.0)
      : now
    expires = expiresMs > 0
      ? Date(timeIntervalSince1970: expiresMs / 1000.0)
      : now.addingTimeInterval(2 * 3600)

    let left = expires.timeIntervalSince(now)
    if left <= 1 { phase = .expired }
    else if left < 5 * 60 { phase = .critical }
    else if left < 15 * 60 { phase = .expiring }
    else { phase = .active }
  }
}

// MARK: - Componentes (sempre cores sólidas — legíveis na ilha preta)

private struct LiveTimer: View {
  let end: Date
  let color: Color
  var size: CGFloat = 12

  var body: some View {
    Group {
      if end.timeIntervalSinceNow > 1 {
        Text(timerInterval: Date()...end, countsDown: true)
      } else {
        Text("0:00")
      }
    }
    .font(.system(size: size, weight: .bold, design: .rounded))
    .monospacedDigit()
    .foregroundColor(color)
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }
}

private struct LiveIcon: View {
  let phase: Phase
  var size: CGFloat = 20

  var body: some View {
    Image(systemName: phase.symbol)
      .font(.system(size: size, weight: .semibold))
      .foregroundColor(phase.color)
      .shadow(color: phase.color.opacity(0.45), radius: 3, x: 0, y: 0)
  }
}

// MARK: - Dynamic Island

private struct IslandExpandedContent: View {
  let snap: Snap

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 10) {
        LiveIcon(phase: snap.phase, size: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text(snap.phase.label)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
          Text(snap.name)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.75))
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        VStack(alignment: .trailing, spacing: 0) {
          LiveTimer(end: snap.expires, color: snap.phase.color, size: 22)
          Text("restante")
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.white.opacity(0.45))
        }
      }

      if !snap.hasRealData {
        Text("Abra o app para sincronizar os dados do check-in.")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.white.opacity(0.55))
      }
    }
    .padding(.horizontal, 6)
    .padding(.bottom, 4)
  }
}

// MARK: - Lock screen

private struct LockContent: View {
  let snap: Snap

  var body: some View {
    HStack(spacing: 12) {
      LiveIcon(phase: snap.phase, size: 24)
      VStack(alignment: .leading, spacing: 3) {
        Text(snap.phase.label)
          .font(.system(size: 11, weight: .heavy))
          .foregroundColor(snap.phase.color)
        Text(snap.name)
          .font(.system(size: 15, weight: .bold))
          .foregroundColor(.white)
          .lineLimit(1)
      }
      Spacer()
      LiveTimer(end: snap.expires, color: .white, size: 18)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

// MARK: - Widget

struct CheckInLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      let snap = Snap(context)
      LockContent(snap: snap)
        .activityBackgroundTint(snap.phase.color.opacity(0.35))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let snap = Snap(context)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          LiveIcon(phase: snap.phase, size: 24)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          LiveTimer(end: snap.expires, color: snap.phase.color, size: 16)
            .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.center) {
          Text(snap.phase.label)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          IslandExpandedContent(snap: snap)
        }
      } compactLeading: {
        LiveIcon(phase: snap.phase, size: 16)
      } compactTrailing: {
        LiveTimer(end: snap.expires, color: snap.phase.color, size: 11)
          .frame(minWidth: 38)
      } minimal: {
        LiveIcon(phase: snap.phase, size: 14)
      }
      .keylineTint(snap.phase.color)
    }
  }
}
