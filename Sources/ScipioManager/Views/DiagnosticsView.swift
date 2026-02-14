import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppState.self) private var appState
    @State private var results: [DiagnosticResult] = []
    @State private var isRunning = false

    var passedCount: Int { results.filter(\.passed).count }
    var failedCount: Int { results.filter { !$0.passed }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryBar
                resultsList
            }
            .padding(24)
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ActionButton("Run Checks", icon: "stethoscope", isRunning: isRunning) {
                    await runDiagnostics()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task { await runDiagnostics() }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        HStack(spacing: 24) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(passedCount) passed")
                    .fontWeight(.medium)
            }

            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(failedCount > 0 ? .red : .secondary.opacity(0.3))
                Text("\(failedCount) failed")
                    .fontWeight(.medium)
                    .foregroundStyle(failedCount > 0 ? .primary : .secondary)
            }

            Spacer()

            if isRunning {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Results

    private var resultsList: some View {
        ForEach(DiagnosticResult.Category.allCases, id: \.rawValue) { category in
            let categoryResults = results.filter { $0.category == category }
            if !categoryResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        ForEach(Array(categoryResults.enumerated()), id: \.element.id) { index, result in
                            HStack(spacing: 12) {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .red)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(result.name)
                                        .font(.body)
                                    Text(result.detail)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)

                            if index < categoryResults.count - 1 {
                                Divider().padding(.leading, 46)
                            }
                        }
                    }
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
