import PortsCore
import SwiftUI

struct PortRow: View {
    let entry: PortEntry
    let notify: (String, Bool) -> Void
    let closePopover: () -> Void
    let onChanged: () -> Void

    @State private var hovering = false
    @State private var confirmingKill = false
    @State private var busy = false

    var body: some View {
        HStack(spacing: 10) {
            Text(String(entry.port))
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.processName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("PID \(String(entry.pid)) · \(entry.address)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(entry.isExposed ? .orange : .secondary)
                        .lineLimit(1)
                    if entry.isExposed {
                        Text("LAN")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 0.5)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                            .help("Bound to all interfaces — reachable from your local network")
                    }
                }
            }

            Spacer(minLength: 4)

            // Actions stay visible (dimmed) instead of appearing on hover, so
            // keyboard users can see what they're tabbing onto.
            if confirmingKill {
                HStack(spacing: 4) {
                    Button("Cancel") { confirmingKill = false }
                        .controlSize(.small)
                        .disabled(busy)
                    Button(role: .destructive) {
                        kill()
                    } label: {
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Kill")
                        }
                    }
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(busy)
                }
            } else {
                HStack(spacing: 2) {
                    Button {
                        openInBrowser()
                    } label: {
                        Image(systemName: "globe")
                    }
                    .buttonStyle(.borderless)
                    .help("Open localhost:\(String(entry.port)) in browser")
                    .accessibilityLabel("Open port \(entry.port) in browser")

                    Button {
                        confirmingKill = true
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Kill \(entry.processName)")
                    .accessibilityLabel("Kill \(entry.processName), PID \(entry.pid)")
                }
                .opacity(hovering ? 1 : 0.55)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { inside in
            hovering = inside
            if !inside && !busy { confirmingKill = false }
        }
        .contextMenu {
            Button("Copy Port") { copy(String(entry.port)) }
            Button("Copy PID") { copy(String(entry.pid)) }
            Button("Copy URL") { copy("http://localhost:\(entry.port)") }
        }
    }

    private func openInBrowser() {
        if PortService.openInBrowser(port: entry.port) {
            closePopover()
        } else {
            notify("Failed to open localhost:\(entry.port)", true)
        }
    }

    private func kill() {
        busy = true
        Task { @MainActor in
            do {
                let killed = try await PortService.kill(pid: entry.pid)
                notify("Killed \(killed.processName) (PID \(killed.pid))", false)
            } catch {
                notify(error.localizedDescription, true)
            }
            busy = false
            confirmingKill = false
            onChanged()
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
