import PortsCore
import SwiftUI

/// The ⌘K overlay: type a port, kill whatever listens on it.
///
/// Rendered as an in-view overlay rather than a `.sheet` on purpose — sheets
/// presented inside an NSPopover make AppKit resize and displace the popover
/// window, which then reopens misaligned.
///
/// If several processes share the port (SO_REUSEPORT, split v4/v6 listeners)
/// every one of them is signalled and the outcome reported honestly.
struct KillByPortView: View {
    let notify: (String, Bool) -> Void
    let onKilled: () -> Void
    let onClose: () -> Void

    @State private var input = ""
    @State private var busy = false
    @State private var fieldError: String?
    @FocusState private var fieldFocused: Bool

    /// Strict parse: `Int.init` rejects "1e3", "3000.5" and friends outright,
    /// so nothing sneaks through as a different port than what was typed.
    private var parsedPort: Int? {
        guard let port = Int(input.trimmingCharacters(in: .whitespaces)),
              (1...65535).contains(port) else { return nil }
        return port
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.3)
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 10) {
                Text("Kill process by port")
                    .font(.headline)
                Text("Enter the port number to terminate its process.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("e.g. 3000", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospacedDigit())
                    .focused($fieldFocused)
                    .onSubmit(submit)

                if let fieldError {
                    Text(fieldError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { onClose() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(busy)
                    Button(role: .destructive, action: submit) {
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Kill")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .tint(.red)
                    .disabled(busy || parsedPort == nil)
                }
            }
            .padding(16)
            .frame(width: 300)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
            .shadow(radius: 16, y: 4)
            .padding(.top, 80)
        }
        .onAppear { fieldFocused = true }
    }

    private func submit() {
        guard let port = parsedPort else {
            fieldError = "Enter a valid port (1–65535)."
            return
        }
        fieldError = nil
        busy = true
        Task { @MainActor in
            do {
                let outcomes = try await PortService.killAll(onPort: port)
                let killed = outcomes.filter(\.success)
                let failed = outcomes.filter { !$0.success }
                if failed.isEmpty {
                    let names = killed.map(\.processName).joined(separator: ", ")
                    notify(killed.count == 1
                        ? "Killed \(names) on port \(port)"
                        : "Killed \(killed.count) processes on port \(port) (\(names))", false)
                    onKilled()
                    onClose()
                } else {
                    let detail = failed.compactMap(\.message).joined(separator: " ")
                    fieldError = killed.isEmpty
                        ? detail
                        : "Killed \(killed.count) of \(outcomes.count) processes. \(detail)"
                    onKilled()
                }
            } catch {
                fieldError = error.localizedDescription
            }
            busy = false
        }
    }
}
