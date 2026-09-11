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
        ZStack {
            LinearGradient(
                colors: [Color.controlKitGreen, Color(red: 0.04, green: 0.12, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 22) {
                    logo
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ControlKit")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text("Apple platform automation")
                            .font(.title2)
                            .foregroundStyle(Color.controlKitCream.opacity(0.78))
                    }
                }

                Text("A clean-room runner for reliable black-box testing across Apple platforms.")
                    .font(.title2.weight(.medium))
                    .frame(maxWidth: 800, alignment: .leading)

                HStack(alignment: .top, spacing: 22) {
                    statusCard
                    informationCard
                }
            }
            .foregroundStyle(Color.controlKitCream)
            .padding(64)
            .frame(maxWidth: 1200, alignment: .leading)
        }
    }

    // MARK: - Private

    private var logo: some View {
        Text("XC\nRS")
            .font(.system(size: 38, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(-10)
            .foregroundStyle(Color.controlKitGreen)
            .frame(width: 124, height: 124)
            .background(Color.controlKitCream, in: RoundedRectangle(cornerRadius: 30))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Runner online", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("The XCTest host is ready to receive ControlKit automation requests.")
                .foregroundStyle(Color.controlKitCream.opacity(0.78))
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(title: "Project", value: "XCRSControlKit")
            infoRow(title: "Creator", value: "smbCloud")
            infoRow(title: "Platform", value: "tvOS")
            infoRow(title: "Purpose", value: "Native UI automation runner")
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.controlKitCream.opacity(0.62))
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

private extension Color {
    static let controlKitGreen = Color(red: 0.106, green: 0.263, blue: 0.196)
    static let controlKitCream = Color(red: 0.961, green: 0.953, blue: 0.925)
}
