//
//  SettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-01.
//

import Foundation
import SwiftUI
import LaunchAtLogin
import Combine
import OSLog

struct SettingsView: View {
    
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    internal var logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "settingsview")

    var body: some View {
        TabView {
            GeneralSettings().tabItem {
                Image(systemName: "gear")
                Text("General")
            }.environmentObject(s)

            CGMSettings().tabItem{
                Image(systemName: "bandage.fill")
                Text("CGM")
            }.environmentObject(s).environmentObject(g)
        }.padding()
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var s: SettingsStore

    internal var logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "provider")

    var body: some View {
        Form {
            VStack {
                Text("View Options").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                HStack {
                    Text("Glucose Unit").frame(width: 130, alignment: .leading)
                    Spacer()
                    Picker("", selection: $s.glucoseUnit) {
                        ForEach(GlucoseUnit.allCases) { unit in
                            Text(unit.presentable).tag(unit)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }
                HStack {
                    Text("High Threshold").frame(width: 130, alignment: .leading)
                    Spacer()
                    VStack {
                        Slider(value: Binding(
                            get: { s.highThreshold },
                            set: {
                                if $0 > s.lowThreshold {
                                    s.highThreshold = $0
                                } else {
                                    s.highThreshold = (s.lowThreshold + 1)
                                }
                            }
                        ), in: 40...400) {
                        } minimumValueLabel: {
                            Text("\(formatGlucoseForDisplay(settings: s, glucose: 40))")
                        } maximumValueLabel: {
                            Text("\(formatGlucoseForDisplay(settings: s, glucose: 400))")
                        }
                    }.frame(width:270, alignment: .leading)
                    Spacer()
                    Text(formatGlucoseForDisplay(settings: s, glucose: s.highThreshold)).frame(width:50, alignment: .trailing)
                }
                HStack {
                    Text("Low Threshold").frame(width: 130, alignment: .leading)
                    Spacer()
                    VStack {
                        Slider(value: Binding(
                            get: { s.lowThreshold },
                            set: {
                                if $0 < s.highThreshold {
                                    s.lowThreshold = $0
                                } else {
                                    s.lowThreshold = (s.highThreshold - 1)
                                }
                            }
                            ), in: 40...400) {
                        } minimumValueLabel: {
                            Text("\(formatGlucoseForDisplay(settings: s, glucose: 40))")
                        } maximumValueLabel: {
                            Text("\(formatGlucoseForDisplay(settings: s, glucose: 400))")
                        }
                    }.frame(width:270, alignment: .leading)
                    Spacer()
                    Text(formatGlucoseForDisplay(settings: s, glucose: s.lowThreshold)).frame(width:50, alignment: .trailing)
                }

                HStack {
                    Text("Show Delta").frame(width: 260, alignment: .leading)
                    Spacer()
                    Toggle(isOn: $s.showDelta, label: {}).toggleStyle(.switch).tint(.blue)
                }

                HStack {
                    Text("Always Show Time Since Reading").frame(width: 260, alignment: .leading)
                    Spacer()
                    Toggle(isOn: $s.showTimeSince, label: {}).toggleStyle(.switch).tint(.blue)
                }
                HStack {
                    Text("Will always show if reading is over 5 minutes old").font(.footnote)
                    Spacer()
                }

                HStack {
                    Text("Enable Colored Icon When Out of Range").frame(width: 260, alignment: .leading)
                    Spacer()
                    Toggle(isOn: $s.showMenuBarIcon, label: {}).toggleStyle(.switch).tint(.blue)
                }
                HStack {
                    (
                        Text("Shows a ") +
                        Text(Image(systemName: "drop")) +
                        Text(" when low, a ") +
                        Text(Image(systemName: "drop.fill")) +
                        Text(" when high, and otherwise ") +
                        Text(Image(systemName: "drop.halffull"))
                     ).font(.footnote)
                    Spacer()
                }

                HStack {
                    Text("Enable Hovering on Graph")
                    Spacer()
                    Toggle(isOn: $s.hoverableGraph, label: {}).toggleStyle(.switch).tint(.blue).onChange(of: s.hoverableGraph, initial: false) {
                        s.save()
                    }
                }
                HStack {
                    Text("Enabling this setting will add a large glucose readout at the top of the window").font(.footnote)
                    Spacer()
                }

                Text("Launch Behavior").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                HStack {
                    Text("Launch at Login").frame(width: 260, alignment: .leading)
                    Spacer()
                    LaunchAtLogin.Toggle("").toggleStyle(.switch).tint(.blue)
                }
                Spacer()
                HStack {
                    Button("Quit GlucoseBar") {
                        NSApplication.shared.terminate(nil)
                    }
                    Spacer()
                    Button("Save") {
                        s.save()
                    }
                }.padding(.top, 10)
                Spacer()
                Text("\(Bundle.main.appName) Version: \(Bundle.main.appVersionLong) (\(Bundle.main.appBuild)) ").font(.footnote).padding(2)
            }
        }.frame(minWidth: 475, maxWidth: 475, minHeight: 395, maxHeight: 395)
    }
}

struct CGMSettings: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State var isValidating: Bool = false
    @State var isDeletingCGMProvider: Bool = false
    @State var cgmCredentialsError: Bool = false
    @State var cgmCredentialsSuccess: Bool = false
    @State var validatedProvider: CGMProvider = .null

    @FocusState var nsSecretFailedValidationFocus: Bool
    @State var nsSecretFailedValidation: Bool = false

    internal var logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "provider")

    var body: some View {
        Form {
            VStack {
                HStack {
                    Text("CGM Provider").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    Picker("", selection: $s.cgmProvider) {
                        ForEach(CGMProvider.allCases) { provider in
                            if provider != .null && provider != .librelinkup {
                                Text(provider.presentable).tag(provider)
                            }
                        }
                    }.padding(.top, 10)
                    .pickerStyle(SegmentedPickerStyle()) // Work around since normal selects close the settings window on us 🤪
                }

                VStack {
                    if s.cgmProvider == .simulator {
                        Text("The simulator has no settings and is a CGM provider implemented to enable you to test the application without connecting a real CGM provider such as Dexcom, Libre or Nightscout.").padding(.top, 10)
                    }

                    if s.cgmProvider == .nightscout {
                        HStack {
                            Text("Server URL").frame(width: 130, alignment: .leading)
                            Spacer()
                            TextField("", text: $s.nsURL).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        HStack {
                            Text("Token").frame(width: 130, alignment: .leading)
                            Spacer()
                            TextField("", text: $s.nsSecret).textFieldStyle(RoundedBorderTextFieldStyle())
                                .focused($nsSecretFailedValidationFocus)
                        }
                        if nsSecretFailedValidation {
                            HStack {
                                Text("The Token is required for GlucoseBar to function correctly. Please ensure your Nightscout instance has one set up and use it here.").font(.footnote).foregroundColor(.red)
                                Spacer()
                            }
                        }
                        HStack {
                            Text("This token needs to have the permission \"readable\" in Nightscout.").font(.footnote)
                            Spacer()
                        }
                    }

                    if s.cgmProvider == .dexcomshare {
                        HStack {
                            Text("Dexcom Region").frame(width: 130, alignment: .leading)
                            Spacer()
                            Picker("", selection: $s.dxServer) {
                                ForEach(DexcomServer.allCases) { server in
                                    Text(server.presentable).tag(server)
                                }
                            }.pickerStyle(SegmentedPickerStyle()).frame(alignment: .trailing)
                        }

                        HStack {
                            Text("Email or Username").frame(width: 130, alignment: .leading)
                            Spacer()
                            TextField("", text: $s.dxEmail).autocorrectionDisabled(true)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        HStack {
                            Text("Password").frame(width: 130, alignment: .leading)
                            Spacer()
                            SecureField("", text: $s.dxPassword).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        Text("These credentials are the ones from your primary Dexcom account. You must also have at least one follower in the Dexcom app.").font(.footnote).fixedSize(horizontal: false, vertical: true)
                    }

//                    if s.cgmProvider == .librelinkup {
//                        HStack {
//                            Text("Email").frame(width: 130, alignment: .leading)
//                            Spacer()
//                            TextField("", text: $s.libreUsername).autocorrectionDisabled(true)
//                                .textFieldStyle(RoundedBorderTextFieldStyle())
//                        }
//                        HStack {
//                            Text("Password").frame(width: 130, alignment: .leading)
//                            Spacer()
//                            SecureField("", text: $s.librePassword).textFieldStyle(RoundedBorderTextFieldStyle())
//                        }
//                        HStack {
//                            Text("Following").frame(width: 130, alignment: .leading)
//                            Spacer()
//                            if cgmCredentialsSuccess {
//                                g.provider.getConnectionView(s: s)
//                            } else {
//                                Text("Please click \"Test Connection\" to display following options.").font(.footnote)
//                            }
//                        }
//                    }
                    Spacer()
                    HStack {
                        if s.cgmProvider != .simulator {
                            Button(action: {
                                isDeletingCGMProvider = true
                            }) {
                                Image(systemName: "trash.fill").foregroundColor(.red)
                            }.disabled(isValidating || ![.nightscout, .dexcomshare, .librelinkup].contains(s.cgmProvider)).help("Delete data for \(s.cgmProvider.presentable)?").confirmationDialog(
                                "Are you sure you want to remove data for \(s.cgmProvider.presentable)?",
                                isPresented: $isDeletingCGMProvider
                            ) {
                                Button("Delete") {
                                    DispatchQueue.main.async {
                                        s.deleteCGMProvider()
                                        if g.provider.type == .librelinkup {
                                            g.provider.connections = []
                                            g.provider.connectionID = ""
                                        }
                                    }
                                    isDeletingCGMProvider = false
                                }
                                Button("Cancel", role: .cancel) {
                                    isDeletingCGMProvider = false
                                }
                            }

                            Button(action: {
                                nsSecretFailedValidation = false
                                if s.cgmProvider == .nightscout && s.nsSecret.count == 0 {
                                    logger.info("Nightscout without token, tell user to fix and abort")
                                    nsSecretFailedValidation = true
                                    return
                                }

                                isValidating = true
                                Task {
                                    validatedProvider = s.cgmProvider
                                    let providerTest = await s.testCGMProvider()

                                    cgmCredentialsError = !providerTest
                                    cgmCredentialsSuccess = providerTest
                                    isValidating = false
                                    s.validSettings = providerTest

                                    self.logger.debug("test complete. \(g.provider.connectionID)")
                                }
                            }) {
                                Text("Test Connection")
                            }.disabled(isValidating) // TODO: State var for if it's currently testing
                        }
                        if g.provider.providerIssue != nil {
                            Text("Provider issue: \(g.provider.providerIssue ?? "Unknown")")
                        }
                        if !isValidating && cgmCredentialsError && s.cgmProvider == validatedProvider {
                            Text("Invalid credentials or service unreachable").foregroundColor(.orange)
                            Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                        }
                        if !isValidating && cgmCredentialsSuccess && s.cgmProvider == validatedProvider {
                            HStack {
                                Text("Connection OK").foregroundColor(.green)
                                Image(systemName: "checkmark.circle").foregroundColor(.green)
                            }
                        }
                        if isValidating {
                            ProgressView()
                                .controlSize(.small)
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(.leading, 2)
                        }
                        Spacer()
                        Button("Save") {
                            nsSecretFailedValidation = false
                            if s.cgmProvider == .nightscout && s.nsSecret.count == 0 {
                                logger.info("Nightscout without token, tell user to fix and abort")
                                nsSecretFailedValidation = true
                                return
                            }
                            s.save()
                        }.disabled(isValidating)
                    }
                }
            }
        }.frame(minWidth: 475, maxWidth: 475, minHeight: 200, maxHeight: 200, alignment: .topLeading)
    }
}

#Preview {
    SettingsView().environmentObject(SettingsStore()).environmentObject(Glucose())
}
