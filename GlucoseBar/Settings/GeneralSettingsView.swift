//
//  GeneralSettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI
import LaunchAtLogin

struct GeneralSettingsView: View {
    @EnvironmentObject var uc: UpdateChecker
    @EnvironmentObject var sourceManager: SourceManager

    @State private var showDebugConfirmation = false
    @State private var syncCredentialsToICloud = CredentialSyncPreference.isEnabled
    @State private var credentialSyncError: String?

    var body: some View {
        ScrollView {
            VStack {
                GroupBox {
                    HStack {
                        if let image = NSImage(named: "AppIcon") {
                            Image(nsImage: image)
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture(count: 4) {
                                    guard sourceManager.sources.first?.settings.debugMode != true else { return }
                                    showDebugConfirmation = true
                                }
                                .alert("Enable Debug Mode?", isPresented: $showDebugConfirmation) {
                                    Button("Enable") {
                                        sourceManager.sources.first?.settings.setDebugMode(true)
                                        sourceManager.refreshToken = UUID()
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("Debug mode logs additional information for troubleshooting purposes.")
                                }
                        }
                        Spacer()
                        VStack {
                            Text("Hi,\nI'm GlucoseBar.").font(.title).multilineTextAlignment(.center)
                            Text(verbatim: "Version: \(Bundle.main.appVersionLong) (\(Bundle.main.appBuild)) ").font(.footnote)
                            Text(verbatim: uc.channel == .appStore ? "Mac App Store" : uc.channel == .testFlight ? "TestFlight" : "Direct Download").font(.footnote).foregroundStyle(.secondary)
                            Button(action: {
                                NSWorkspace.shared.open(URL(string: "https://glucosebar.t1d.tools")!)
                            }) {
                                HStack {
                                    Text(verbatim: "glucosebar.t1d.tools").font(.footnote)
                                }
                            }.buttonStyle(.plain).foregroundStyle(.blue).padding(.top, 2)
                            Button(action: {
                                NSWorkspace.shared.open(URL(string: "https://github.com/t1dtools/glucosebar")!)
                            }) {
                                HStack {
                                    Text(verbatim: "GitHub").font(.footnote)
                                }
                            }.buttonStyle(.plain).foregroundStyle(.blue).padding(.top, 2)
                        }
                        Spacer()
                    }.padding()
                }

                Text("Launch Behavior").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Launch at Login")
                            Text("Automatically start GlucoseBar when you log in to your Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        LaunchAtLogin.Toggle("").toggleStyle(.switch).tint(.blue).fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }.padding()
                }

                Text("Credentials").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sync credentials with iCloud Keychain")
                                Text("CGM credentials are kept in this Mac's Keychain. Turning this on also stores them in iCloud Keychain, so they come back if you set up a new Mac from scratch.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: $syncCredentialsToICloud)
                                .toggleStyle(.switch).tint(.blue).fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                                .onChange(of: syncCredentialsToICloud) { _, _ in applyCredentialSyncChange() }
                        }
                        Text("Only has an effect if iCloud Keychain is switched on in System Settings — GlucoseBar cannot tell whether it is. This includes the credentials of a CGM you monitor for someone else, and deleting a source will then remove its credentials on your other devices as well.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let credentialSyncError {
                            Text(credentialSyncError)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding()
                }
            }.padding()
        }
    }

    /// Re-stores every source's credentials in the class the toggle now selects.
    ///
    /// The switch is explicit rather than automatic because the two keychain item
    /// classes are separate spaces: an item written as synchronizable is not returned
    /// by a query for local items, and vice versa. Migrating them together is what
    /// keeps exactly one copy per credential and avoids the app silently failing to
    /// find a credential it still has.
    private func applyCredentialSyncChange() {
        UserDefaults.standard.set(syncCredentialsToICloud, forKey: CredentialSyncPreference.defaultsKey)

        let mode: CredentialSyncMode = syncCredentialsToICloud ? .iCloudKeychain : .local
        let store = KeychainCredentialStore()
        var failures: [String] = []

        for source in sourceManager.sources {
            do {
                try store.migrateSecrets(for: source.id, to: mode)
            } catch {
                failures.append(source.settings.sourceName)
            }
        }

        credentialSyncError = failures.isEmpty
            ? nil
            : String(localized: "GlucoseBar could not move the credentials for: ", comment: "Prefix of the message shown when moving credentials between keychain classes fails, followed by source names") + failures.joined(separator: ", ")
    }
}
