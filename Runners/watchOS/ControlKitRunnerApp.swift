import SwiftUI

@main
struct ControlKitRunnerApp: App {
    // MARK: - Internal

    var body: some Scene {
        WindowGroup {
            ControlKitShowcaseView()
        }
    }
}

private struct ControlKitShowcaseView: View {
    // MARK: - Internal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    logo
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ControlKit")
                            .font(.headline)
                        Text("watchOS")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                statusCard
                informationCard
            }
            .padding(12)
        }
        .background(Color.controlKitGreen.ignoresSafeArea())
        .foregroundStyle(Color.controlKitCream)
    }

    // MARK: - Private

    private var logo: some View {
        Text("XC\nRS")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(-3)
            .foregroundStyle(Color.controlKitGreen)
            .frame(width: 40, height: 40)
            .background(Color.controlKitCream, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Runner online", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
            Text("Ready for ControlKit automation requests.")
                .font(.caption2)
                .foregroundStyle(Color.controlKitCream.opacity(0.78))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow(title: "Project", value: "XCRSControlKit")
            infoRow(title: "Creator", value: "smbCloud")
            infoRow(title: "Purpose", value: "Companion automation runner")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.controlKitCream.opacity(0.62))
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

private extension Color {
    static let controlKitGreen = Color(red: 0.106, green: 0.263, blue: 0.196)
    static let controlKitCream = Color(red: 0.961, green: 0.953, blue: 0.925)
}
