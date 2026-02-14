import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false

    var passedCount: Int { results.filter(\.passed).count }
    var failedCount: Int { results.filter { !$0.passed }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryBar
                resultsList
            }
            .padding()
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ActionButton("Run All Checks", icon: "stethoscope", isRunning: isRunning) {
                    await runDiagnostics()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task { await runDiagnostics() }
    }

    private var summaryBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(passedCount) passed")
                    .fontWeight(.medium)
            }

            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("\(failedCount) failed")
                    .fontWeight(.medium)
            }

            Spacer()

            if isRunning {
                ProgressView()
                    .controlSize(.small)
                Text("Running...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private var resultsList: some View {
        ForEach(DiagnosticResult.Category.allCases, id: \.rawValue) { category in
            let categoryResults = results.filter { $0.category == category }
            if !categoryResults.isEmpty {
                GroupBox(category.rawValue) {
                    VStack(spacing: 8) {
                        ForEach(categoryResults) { result in
                            HStack(spacing: 10) {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .red)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .fontWeight(.medium)
                                    Text(result.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)

                            if result.id != categoryResults.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func runDiagnostics() async {
        guard let scipioDir = appState.scipioDir else { return }
        isRunning = true
        defer { isRunning = false }

        results = await DiagnosticsService.runAll(scipioDir: scipioDir)
        appState.diagnosticResults = results
        appState.addActivity("Diagnostics: \(passedCount)/\(results.count) passed", type: failedCount > 0 ? .warning : .success)
    }
}
