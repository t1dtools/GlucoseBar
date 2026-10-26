//
//  DebugSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2026-06-12.
//

import SwiftUI

struct DebugSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State private var showCopiedConfirmation = false
    @State private var showResetConfirmation = false
    @State private var showLeaveDebugModeConfirmation = false

    /// Draft for the VCR proxy field, kept local so the address is only written
    /// when Save is pressed. It used to be saved on every keystroke, which
    /// persisted half-typed addresses that the providers then crashed on.
    @State private var vcrProxyDraft: String = ""
    @State private var vcrProxyError: String?

    var logPath: String {
        DebugLogger.shared.currentLogURL?.path
            ?? "Log file not yet created"
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("Debug Logging")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Debug Mode Enabled")
                                Text("All log statements are written to a file in Application Support.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Current log file")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(logPath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 8) {
                            Button {
                                if let url = DebugLogger.shared.currentLogURL {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } else if let dir = FileManager.default.urls(
                                    for: .applicationSupportDirectory, in: .userDomainMask
                                ).first?.appendingPathComponent("tools.t1d.GlucoseBar/logs") {
                                    NSWorkspace.shared.open(dir)
                                }
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(logPath, forType: .string)
                                showCopiedConfirmation = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    showCopiedConfirmation = false
                                }
                            } label: {
                                Label(
                                    showCopiedConfirmation ? "Copied!" : "Copy Path",
                                    systemImage: showCopiedConfirmation ? "checkmark" : "doc.on.doc"
                                )
                            }
                        }
                    }
                    .padding(6)
                }

                Text("Log files are stored in ~/Library/Application Support/tools.t1d.GlucoseBar/logs/. Each session creates a new debug.log; the previous session is renamed with a timestamp.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)

                Text("VCR Proxy")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("VCR proxy address")
                            TextField("http://127.0.0.1:8787", text: $vcrProxyDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button("Save") { saveVCRProxyAddress() }
                                .disabled(vcrProxyDraft == s.vcrProxyAddress)
                        }
                        if let vcrProxyError {
                            Text(vcrProxyError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Empty = production URLs. When set, all providers route through this address (e.g. the glucosebar-vcr emulator) for recording or replay. Debug mode only. Saving recreates the providers so it takes effect immediately.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .onAppear { vcrProxyDraft = s.vcrProxyAddress }
                }

                Text("Reset Data")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset All Data")
                                Text("Removes all saved settings and returns the app to its initial state, while keeping Debug Mode enabled.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Reset All Data", role: .destructive) {
                                showResetConfirmation = true
                            }
                        }
                    }.padding(6)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Disable Debug Mode")
                                Text("Removes the debug menu from the settings panel and stops writing logs to disk for each session. Recommended if you are not a developer or helping a developer understand a problem.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Button("Disable Debug Mode", role: .destructive) {
                                showLeaveDebugModeConfirmation = true
                            }
                        }
                    }.padding(6)
                }
            }.padding()
        }
        .confirmationDialog(
            "Reset All Data",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All Data", role: .destructive) {
                Task { await s.resetApplication() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all settings, and restart the application. This cannot be undone.")
        }.confirmationDialog(
            "Disable Debug Mode",
            isPresented: $showLeaveDebugModeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disable Debug Mode", role: .destructive) {
                Task { await s.disableDebugMode() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disable Debug Mode which will stop GlucoseBar writing log files to your computer and remove the Debug menu from the settings panel.")
        }
    }

    /// Validates and persists the VCR proxy address, then recreates the providers
    /// so it takes effect. The address is only read when a provider is built, so
    /// saving without rebuilding would look like it did nothing.
    private func saveVCRProxyAddress() {
        let trimmed = ProviderURL.cleaned(vcrProxyDraft)

        if trimmed.isEmpty {
            vcrProxyError = nil
            s.vcrProxyAddress = ""
            s.save()
            g.reset(s)
            return
        }

        guard let url = ProviderURL.httpURL(from: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            vcrProxyError = String(localized: "The VCR proxy address must start with http:// or https://", comment: "Validation message for a malformed VCR proxy address in the debug settings screen")
            return
        }

        vcrProxyError = nil
        s.vcrProxyAddress = url.absoluteString
        vcrProxyDraft = url.absoluteString
        s.save()
        g.reset(s)
    }
}

#Preview {
    DebugSettingsView()
        .environmentObject(SettingsStore())
        .environmentObject(Glucose(SettingsStore()))
        .frame(width: 500)
}
