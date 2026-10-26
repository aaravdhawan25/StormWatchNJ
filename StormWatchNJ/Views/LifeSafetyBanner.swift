import SwiftUI
import UIKit

// the red alert shown whenever a report involves utility lines
struct LifeSafetyBanner: View {
    // street address to read to the dispatcher, when known
    var locationText: String?

    @State private var unavailable: Unavailable?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Immediate life-safety risk")
                        .font(.subheadline.weight(.bold))
                    Text("Do not approach. Stay at least \(UtilityHandoff.safeDistanceFeet) feet back and treat every wire as live.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let locationText {
                Text("Tell the dispatcher: \(locationText)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                callButton(title: "Call 911", number: "911", url: UtilityHandoff.emergencyURL, prominent: true)
                callButton(title: "Call \(UtilityHandoff.pseg.name)",
                           number: UtilityHandoff.pseg.phoneDisplay,
                           url: UtilityHandoff.callURL(for: UtilityHandoff.pseg),
                           prominent: false)
            }

            Menu {
                ForEach(UtilityHandoff.otherUtilities) { utility in
                    Button("\(utility.name) · \(utility.phoneDisplay)") {
                        open(UtilityHandoff.callURL(for: utility), label: utility.name, number: utility.phoneDisplay)
                    }
                }
            } label: {
                Label("Not a PSE&G area? Other NJ utilities", systemImage: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.78, green: 0.11, blue: 0.11))
        .alert(item: $unavailable) { item in
            Alert(title: Text("Can't place a call from this device"),
                  message: Text("Dial \(item.number) for \(item.label)."),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func callButton(title: String, number: String, url: URL, prominent: Bool) -> some View {
        Button {
            open(url, label: number == "911" ? "emergency services" : title.replacingOccurrences(of: "Call ", with: ""), number: number)
        } label: {
            Label(title, systemImage: "phone.fill")
                .font(.footnote.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(prominent ? Color.white : Color.white.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(prominent ? Color(red: 0.78, green: 0.11, blue: 0.11) : .white)
        }
        .buttonStyle(.plain)
    }

    // show the number if the device can't call
    private func open(_ url: URL, label: String, number: String) {
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened { unavailable = Unavailable(label: label, number: number) }
        }
    }

    private struct Unavailable: Identifiable {
        let label: String
        let number: String
        var id: String { number }
    }
}
