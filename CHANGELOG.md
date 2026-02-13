# Changelog

All notable changes to Macquitto will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-12

Initial release of Macquitto — a native macOS menu bar agent that exposes system sensors and actions to Home Assistant via MQTT.

### Sensors

- **Audio** — volume level, mute state, output device, input device
- **Display Brightness** — built-in display brightness percentage
- **Screen Lock** — locked/unlocked state detection
- **Focus Mode** — active focus mode detection (Do Not Disturb, custom modes)
- **Battery** — charge level and charging state

### Actions

- Set volume (0–100)
- Toggle mute
- Set display brightness (0–100)
- Lock screen

### Features

- Native macOS menu bar app with live sensor readings
- MQTT discovery for automatic Home Assistant entity registration
- Per-sensor enable/disable and configurable poll intervals
- Settings UI with General, MQTT, and Sensors tabs
- TLS/SSL support with client certificate authentication
- Secure password storage in macOS Keychain
- Connection status indicator with auto-reconnect and LWT
- Start at Login via macOS ServiceManagement
- Headless mode (`--headless`) for running without UI
- CLI options: `--config`, `--set-password`, `--show-config`, `--version`
- YAML configuration at `~/.config/macquitto/config.yaml`

### Requirements

- macOS 14 (Sonoma) or later
