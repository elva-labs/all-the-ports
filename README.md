# all the ports

A tiny macOS menu-bar app that shows every TCP port listening on your machine — and lets you kill the process holding it, or open its `localhost` URL in your browser.

Native Swift/SwiftUI. No Electron, no runtime, ~2.5 MB.

## Features

- **Live port list** — every `LISTEN`ing TCP socket, with process name, PID, and bind address. Refreshes every 3 seconds while open (and not at all while closed).
- **Exposure at a glance** — ports bound to all interfaces (`0.0.0.0` / `::`) are flagged **LAN**, because "reachable from your network" is the thing a port list should actually tell you.
- **Kill safely** — two-step confirm, `SIGTERM` (dev servers shut down cleanly), and the PID is re-checked against the live socket list before any signal is sent, so the app can never kill a process it didn't list.
- **⌘K — kill by port** — type a port number, and *every* process listening on it is terminated and reported (`SO_REUSEPORT` workers included), not just the first one found.
- **Open in browser** — one click to `http://localhost:<port>`.
- **Global shortcut** — open the popover from anywhere; recorded natively via [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).
- **Filter** by port, process name, PID, or address; copy port / PID / URL from the context menu.
- **Launch at login**, dark mode, keyboard-accessible actions — the usual native niceties.

## Install

### Homebrew (recommended)

```sh
brew install --cask elva-labs/elva/all-the-ports
```

Or grab the zip from the [latest release](https://github.com/elva-labs/all-the-ports/releases/latest) — releases are signed and notarized (Developer ID), so there are no Gatekeeper warnings either way.

### Build from source

Requires macOS 13+ and Xcode 15+ (Swift 5.10).

```sh
git clone https://github.com/elva-labs/all-the-ports.git
cd all-the-ports
make app          # builds build/all the ports.app
make run          # builds and launches it
```

Copy `build/all the ports.app` to `/Applications` if you like it.

## How it works

Ports are discovered with `lsof -nP -iTCP -sTCP:LISTEN` in field-output mode (`-F`), which is robust against process names containing spaces. The parser is a pure function (`PortsCore/LsofParser`) with a unit-test suite covering IPv4/IPv6, wildcard binds, dual-stack dedupe, shared ports, and malformed output. Processes are terminated with `SIGTERM` via `kill(2)` — never through a shell.

`lsof` and the kill path run with absolute paths and a 5-second timeout; failures surface as errors in the UI rather than an empty list.

## Development

```sh
make build        # debug build
make test         # parser unit tests
```

The package has two targets: `PortsCore` (parsing + port service, fully testable, no UI) and `AllThePorts` (AppKit/SwiftUI shell).

## Origin

Started as a [Glaze](https://glaze.app) (Electron/React) prototype, then ported to native Swift so it can be distributed as a plain open-source app.

## License

[MIT](LICENSE) © Elva Group AB
