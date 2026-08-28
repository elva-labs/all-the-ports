import PortsCore
import SwiftUI

struct ContentView: View {
    let openSettings: () -> Void
    let closePopover: () -> Void

    @State private var ports: [PortEntry] = []
    @State private var loadError: String?
    @State private var isInitialLoad = true
    @State private var search = ""
    @State private var showKillByPort = false
    @State private var notice: Notice?
    @State private var noticeDismissTask: Task<Void, Never>?

    struct Notice: Equatable {
        var text: String
        var isError: Bool
    }

    private var filtered: [PortEntry] {
        let term = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !term.isEmpty else { return ports }
        return ports.filter {
            String($0.port).contains(term)
                || $0.processName.lowercased().contains(term)
                || String($0.pid).contains(term)
                || $0.address.lowercased().contains(term)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            TextField("Filter by port, process, PID, or address", text: $search)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            Divider()

            content
            Divider()
            footer
        }
        .frame(width: 400, height: 540)
        .overlay {
            if showKillByPort {
                KillByPortView(
                    notify: notify,
                    onKilled: { Task { await refresh() } },
                    onClose: { showKillByPort = false }
                )
            }
        }
        .overlay(alignment: .bottom) { noticeBanner }
        .task { await pollWhileVisible() }
        .onDisappear {
            // The popover hides on outside clicks; a half-typed kill dialog
            // must not still be up the next time it opens.
            showKillByPort = false
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 8) {
            Text("Ports")
                .font(.headline)
            Text("\(ports.count)")
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel("\(ports.count) listening ports")

            Spacer()

            Button {
                showKillByPort = true
            } label: {
                Label("Kill by port…", systemImage: "bolt")
                    .labelStyle(.titleAndIcon)
            }
            .controlSize(.small)
            .keyboardShortcut("k", modifiers: .command)
            .help("Kill the process on a specific port (⌘K)")

            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isInitialLoad {
            Spacer()
            ProgressView()
            Spacer()
        } else if let loadError {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Failed to list ports")
                    .font(.headline)
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await refresh() } }
            }
            .padding(.horizontal, 24)
            Spacer()
        } else if filtered.isEmpty {
            Spacer()
            VStack(spacing: 4) {
                Text(search.isEmpty ? "No listening ports" : "No matching ports")
                    .font(.headline)
                Text(search.isEmpty
                    ? "No TCP ports are currently listening."
                    : "Try a different search term.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { entry in
                        PortRow(entry: entry, notify: notify, closePopover: closePopover) {
                            Task { await refresh() }
                        }
                        Divider().padding(.leading, 10)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit all the ports (⌘Q)")
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice {
            Text(notice.text)
                .font(.caption)
                .lineLimit(3)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(notice.isError ? Color.red.opacity(0.9) : Color.green.opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
                .padding(.bottom, 40)
                .transition(.opacity)
        }
    }

    // MARK: - Data

    /// Refresh every 3 s while the popover is visible. The task is cancelled
    /// when the view disappears, so nothing polls while the popover is hidden.
    private func pollWhileVisible() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    @MainActor
    private func refresh() async {
        do {
            ports = try await PortService.listPorts()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
        isInitialLoad = false
    }

    @MainActor
    private func notify(_ text: String, isError: Bool) {
        noticeDismissTask?.cancel()
        withAnimation { notice = Notice(text: text, isError: isError) }
        noticeDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation { notice = nil }
            }
        }
    }
}
