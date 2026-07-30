import SwiftUI

@main
struct ControlKitRunnerApp: App {
    var body: some Scene {
        WindowGroup {
            ControlKitShowcaseView()
        }
        .defaultSize(width: 820, height: 620)
    }
}

private struct ControlKitShowcaseView: View {
    private let repositoryURL = URL(string: "https://github.com/ondeinference/xcrs-controlkit")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 18) {
                    logo
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ControlKit")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text("Apple platform automation")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("A clean-room runner for reliable black-box testing across Apple platforms.")
                    .font(.title2.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                statusCard
                informationCard

                Link(destination: repositoryURL) {
                    Label("View project on GitHub", systemImage: "arrow.up.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var logo: some View {
        Text("XC\nRS")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .multilineTextAlignment(.center)
            .lineSpacing(-8)
            .foregroundStyle(Color.controlKitGreen)
            .frame(width: 96, height: 96)
            .background(Color.controlKitCream, in: RoundedRectangle(cornerRadius: 24))
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Runner online", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("The XCTest host is ready to receive ControlKit automation requests.")
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(title: "Project", value: "XCRSControlKit")
            infoRow(title: "Creator", value: "smbCloud")
            infoRow(title: "Platform", value: "visionOS")
            infoRow(title: "Purpose", value: "Native spatial automation runner")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
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
