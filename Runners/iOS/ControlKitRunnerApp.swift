import SwiftUI

@main
struct ControlKitRunnerApp: App {
    var body: some Scene {
        WindowGroup {
            ControlKitShowcaseView()
        }
    }
}

private struct ControlKitShowcaseView: View {
    private let repositoryURL = URL(string: "https://github.com/ondeinference/xcrs-controlkit")!

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.controlKitGreen, Color(red: 0.04, green: 0.12, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 18) {
                        logo
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ControlKit")
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("Apple platform automation")
                                .font(.title3)
                                .foregroundStyle(Color.controlKitCream.opacity(0.78))
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
                    .tint(Color.controlKitCream)
                    .foregroundStyle(Color.controlKitGreen)
                }
                .foregroundStyle(Color.controlKitCream)
                .padding(32)
                .frame(maxWidth: 820)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: UIScreen.main.bounds.width, minHeight: UIScreen.main.bounds.height)
        .ignoresSafeArea(.all)
        .statusBarHidden(true)
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
                .foregroundStyle(Color.controlKitCream.opacity(0.78))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
    }

    private var informationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            infoRow(title: "Project", value: "XCRSControlKit")
            infoRow(title: "Creator", value: "smbCloud")
            infoRow(title: "Platform", value: "iOS and iPadOS")
            infoRow(title: "Purpose", value: "Native UI automation runner")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
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
