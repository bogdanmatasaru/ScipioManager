import SwiftUI

// MARK: - Status Badge

struct StatusBadge: View {
    let status: CacheStatus

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch status {
        case .allLayers: return .green
        case .localOnly, .remoteOnly: return .orange
        case .missing: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Stat Card (Dashboard)

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let role: ButtonRole?
    let isRunning: Bool
    let action: () async -> Void

    init(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        isRunning: Bool = false,
        action: @escaping () async -> Void
    ) {
        self.title = title
        self.icon = icon
        self.role = role
        self.isRunning = isRunning
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            Task { await action() }
        } label: {
            Label {
                Text(title)
            } icon: {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
            }
        }
        .disabled(isRunning)
    }
}

// MARK: - Log Console

struct LogConsoleView: View {
    let lines: [LogLine]
    @State private var autoScroll = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Console", systemImage: "terminal")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(timeString(line.timestamp))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                                    .frame(width: 50, alignment: .trailing)
                                Text(line.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(line.stream == .stderr ? .red : .primary)
                                    .textSelection(.enabled)
                            }
                            .id(line.id)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: lines.count) {
                    if autoScroll, let last = lines.last {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(.black.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}

// MARK: - Hero Card (kept for backward compat but unused)

struct HeroCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .accentColor

    var body: some View {
        StatCard(title: title, value: value, icon: icon, tint: color)
    }
}

// MARK: - Cache Layer Card

struct CacheLayerCard: View {
    let name: String
    let icon: String
    let detail: String
    let size: String
    var isPresent: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isPresent ? .secondary : .quaternary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(size)
                .font(.subheadline)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}
