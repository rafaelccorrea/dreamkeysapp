import ActivityKit
import WidgetKit
import SwiftUI

// ⚠️ O nome PRECISA ser EXATAMENTE `LiveActivitiesAppAttributes` — é o que o
// plugin `live_activities` procura. Renomear faz a atividade ser criada mas
// nunca aparecer.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState

  public struct ContentState: Codable, Hashable {}

  var id = UUID()
}

// App Group compartilhado com o app Flutter (precisa ser idêntico ao usado em
// `LiveActivityService._appGroupId` e nas entitlements de Runner + extension).
let sharedDefault = UserDefaults(suiteName: "group.com.dreamkeys.corretor")!

extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String {
    return "\(id)_\(key)"
  }
}

// MARK: - Leitura dos dados vindos do Flutter

private func laUserName(_ ctx: ActivityViewContext<LiveActivitiesAppAttributes>) -> String {
  return sharedDefault.string(forKey: ctx.attributes.prefixedKey("userName")) ?? ""
}

private func laExpiresDate(_ ctx: ActivityViewContext<LiveActivitiesAppAttributes>) -> Date {
  let ms = sharedDefault.double(forKey: ctx.attributes.prefixedKey("expiresAtEpoch"))
  return Date(timeIntervalSince1970: ms / 1000.0)
}

private let laAccent = Color(red: 0.20, green: 0.83, blue: 0.60) // emerald

// MARK: - Componentes reaproveitados

/// Contador regressivo com clamp: se já expirou, mostra "expirado" em vez de
/// estourar o range do `Text(timerInterval:)`.
private struct CountdownText: View {
  let expires: Date
  var font: Font = .caption
  var weight: Font.Weight = .semibold

  var body: some View {
    if expires.timeIntervalSinceNow > 1 {
      Text(timerInterval: Date()...expires, countsDown: true)
        .font(font)
        .fontWeight(weight)
        .monospacedDigit()
        .foregroundColor(.white)
    } else {
      Text("expirado")
        .font(font)
        .fontWeight(weight)
        .foregroundColor(.orange)
    }
  }
}

private struct LockScreenView: View {
  let context: ActivityViewContext<LiveActivitiesAppAttributes>

  var body: some View {
    let expires = laExpiresDate(context)
    let userName = laUserName(context)

    HStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(laAccent.opacity(0.18))
          .frame(width: 44, height: 44)
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(laAccent)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text("Na imobiliária")
          .font(.subheadline)
          .fontWeight(.bold)
          .foregroundColor(.white)
        if !userName.isEmpty {
          Text(userName)
            .font(.caption2)
            .foregroundColor(.white.opacity(0.7))
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 2) {
        CountdownText(expires: expires, font: .title3, weight: .bold)
        Text("até expirar")
          .font(.caption2)
          .foregroundColor(.white.opacity(0.6))
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
      LockScreenView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.88))
        .activitySystemActionForegroundColor(Color.white)
    } dynamicIsland: { context in
      let expires = laExpiresDate(context)
      let userName = laUserName(context)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label {
            Text("Check-in")
              .font(.caption)
              .foregroundColor(.white)
          } icon: {
            Image(systemName: "checkmark.seal.fill")
              .foregroundColor(laAccent)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          CountdownText(expires: expires, font: .title3, weight: .bold)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text(userName.isEmpty ? "Na imobiliária" : userName)
              .font(.caption2)
              .foregroundColor(.white.opacity(0.75))
              .lineLimit(1)
            Spacer()
            Text("toque para check-out")
              .font(.caption2)
              .foregroundColor(.white.opacity(0.5))
          }
        }
      } compactLeading: {
        Image(systemName: "checkmark.seal.fill")
          .foregroundColor(laAccent)
      } compactTrailing: {
        CountdownText(expires: expires)
      } minimal: {
        Image(systemName: "checkmark.seal.fill")
          .foregroundColor(laAccent)
      }
      .keylineTint(laAccent)
    }
  }
}
