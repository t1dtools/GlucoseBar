//
//  CGMView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI

struct CGMSettingsView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    @State var isValidating: Bool = false
    @State var isDeletingCGMProvider: Bool = false
    @State var cgmCredentialsError: Bool = false
    @State var cgmCredentialsSuccess: Bool = false
    @State var validatedProvider: CGMProvider = .null

    @FocusState var nsSecretFailedValidationFocus: Bool
    @State var nsSecretFailedValidation: Bool = false

    struct SimulatorView: View {
        var body: some View {
            HStack {
                Text("The simulator has no settings and is a CGM provider implemented to enable you to test the application without connecting a real CGM provider such as Dexcom or Nightscout.")
                Spacer()
            }
        }
    }

    struct NightscoutView: View {
        @EnvironmentObject var s: SettingsStore
        @EnvironmentObject var g: Glucose

        @FocusState var nsSecretFailedValidationFocus: Bool
        @State var nsSecretFailedValidation: Bool = false
        @State var aidEnabled: Bool

        var body: some View {
            VStack {
                HStack {
                    Text("Server URL").frame(width: 130, alignment: .leading)
                    Spacer()
                    TextField("", text: $s.nsURL).textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("Must start with http:// or https://").font(.footnote)
                    Spacer()
                }
                HStack {
                    Text("Token").frame(width: 130, alignment: .leading)
                    Spacer()
                    TextField("", text: $s.nsSecret).textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($nsSecretFailedValidationFocus).onChange(of: s.nsSecret) { _, newVal in
                            s.nsSecret = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
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

                VStack {
                    HStack {
                        Text("Enable AID Integration")
                        Spacer()
                        Picker("", selection: $aidEnabled) {
                            Text("Yes").tag(true)
                            Text("No").tag(false)
                        }.pickerStyle(SegmentedPickerStyle()).frame(width: 200, alignment: .trailing)
                        .onChange(of: aidEnabled) {
                            s.aidEnableIntegration = aidEnabled
                            s.save()
                        }
                    }
                    HStack {
                        Text("AID stands for Automated Insulin Delivery system. Such systems can provide extra information, like Loop Status, IOB, COB, Eventual Glucose, prediction lines and more.").font(.footnote)
                        Spacer()
                    }
                    HStack {
                        Text("Supported AIDs are AAPS, Loop, OpenAPS, and Trio.").font(.footnote)
                        Spacer()
                    }
                    HStack {
                        Text("Not seeing your AID of choice here? Open an issue on GitHub and lets see if we get it implemented.").font(.footnote)
                        Spacer()
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/t1dtools/GlucoseBar/issues?q=sort%3Aupdated-desc%20state%3Aopen%20label%3Aaid-integration")!)
                        }) {
                            Text("Open GitHub Issues")
                        }
                    }.padding(.top, 20)
                }.padding(.top, 10)
            }
        }
    }

    struct DexcomShareView: View {
        @EnvironmentObject var s: SettingsStore

        var body: some View {
            VStack {
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
        }
    }

    struct LibreLinkUpView: View {
        @EnvironmentObject var s: SettingsStore
        @EnvironmentObject var g: Glucose

        @State var isLoggingIn: Bool = false
        @State var loggedIn: Bool? = nil
        @State var connections: [LibreLinkUp.LibreLinkUpConnectionsResponse] = []

        var body: some View {
            VStack {
                HStack {
                    Text("Region").frame(width: 130, alignment: .leading)
                    Spacer()
                    Picker("", selection: $s.libreServer) {
                        ForEach(LibreServer.allCases) { server in
                            Text(server.presentable).tag(server)
                        }
                    }
                }
                HStack {
                    Text("Email").frame(width: 130, alignment: .leading)
                    Spacer()
                    TextField("", text: $s.libreUsername).autocorrectionDisabled(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("Password").frame(width: 130, alignment: .leading)
                    Spacer()
                    SecureField("", text: $s.librePassword).textFieldStyle(RoundedBorderTextFieldStyle())
                }

                HStack {
                    Button(action: loginAction) {
                        HStack {
                            if isLoggingIn {
                                ProgressView().controlSize(.small).scaleEffect(0.8)
                            }
                            Text("Login")
                        }
                    }
                    .disabled(isLoggingIn || s.libreUsername.isEmpty || s.librePassword.isEmpty)

                    if loggedIn == true {
                        Image(systemName: "checkmark.circle").foregroundColor(.green)
                    } else if loggedIn == false {
                        Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    }
                    Spacer()
                }

                if loggedIn == false {
                    HStack {
                        Text("Invalid credentials. Check your email, password, and region.").foregroundColor(.orange).font(.footnote)
                        Spacer()
                    }
                }

                if loggedIn == true {
                    if connections.isEmpty {
                        HStack {
                            Text("No LibreLinkUp connections found. Ensure you are following at least one FreeStyle Libre user in the LibreLinkUp app.").foregroundColor(.orange).font(.footnote)
                            Spacer()
                        }
                    } else {
                        VStack {
                            Text("Connection").frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            Picker("", selection: $s.libreConnectionID) {
                                Text("Select a patient").tag("").selectionDisabled()
                                ForEach(connections, id: \.patientID) { conn in
                                    Text("\(conn.firstName) \(conn.lastName)").tag(conn.patientID)
                                }
                            }
                        }
                    }
                }

                Text("These credentials are the ones from your LibreLinkUp account. You must be following at least one FreeStyle Libre user in the LibreLinkUp app.").font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }

        func loginAction() {
            isLoggingIn = true
            loggedIn = nil
            connections = []

            Task {
                let temp = LibreLinkUp(
                    username: s.libreUsername,
                    password: s.librePassword,
                    server: s.libreServer,
                    connectionID: s.libreConnectionID
                )

                let success = await temp.login()

                if success {
                    connections = temp.patientConnections
                    if let firstId = connections.first?.patientID, s.libreConnectionID.isEmpty {
                        s.libreConnectionID = firstId
                    }
                }

                loggedIn = success
                isLoggingIn = false
            }
        }
    }

    struct Validation: View {
        @EnvironmentObject var s: SettingsStore
        @EnvironmentObject var g: Glucose

        @State var isValidating: Bool = false
        @State var isDeletingCGMProvider: Bool = false
        @State var cgmCredentialsError: Bool = false
        @State var cgmCredentialsSuccess: Bool = false
        @State var validatedProvider: CGMProvider = .null

        @FocusState var nsSecretFailedValidationFocus: Bool
        @State var nsSecretFailedValidation: Bool = false

        var body: some View {
            if let providerIssue = g.provider.providerIssue {
                Text("Provider issue: \(providerIssue)")
            }
            HStack {
                if s.cgmProvider != .simulator {
                    Button(action: {
                        isDeletingCGMProvider = true
                    }) {
                        Image(systemName: "trash.fill").foregroundColor(.red)
                    }.disabled(isValidating || ![.nightscout, .dexcomshare].contains(s.cgmProvider)).help("Delete data for \(s.cgmProvider.presentable)?").confirmationDialog(
                        "Are you sure you want to remove data for \(s.cgmProvider.presentable)?",
                        isPresented: $isDeletingCGMProvider
                    ) {
                        Button("Delete") {
                            Task {
                                s.deleteCGMProvider()
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
                            nsSecretFailedValidation = true
                            return
                        }

                        isValidating = true
                        Task {
                            validatedProvider = s.cgmProvider
                            g.reset(s)
                            let providerTest = await s.testCGMProvider()

                            cgmCredentialsError = !providerTest
                            cgmCredentialsSuccess = providerTest
                            isValidating = false
                            s.validSettings = providerTest
                        }
                    }) {
                        Text("Test Connection")
                    }.disabled(isValidating)
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
                        nsSecretFailedValidation = true
                        return
                    }
                    s.save()
                    g.reset(s)
                }.disabled(isValidating)
            }
        }
    }

    struct ProviderSelection: View {

        @EnvironmentObject var s: SettingsStore

        var body: some View {
            HStack {
                Text("Provider")
                Spacer()
                Picker("", selection: $s.cgmProvider) {
                    if s.cgmProvider == .null {
                        Text("Select a provider").tag(CGMProvider.null).selectionDisabled()
                    }
                    ForEach(CGMProvider.allCases) { provider in
                        if provider != .null {
                            Text(provider.presentable).tag(provider)
                        }
                    }
                }.frame(width: 200, alignment: .trailing).onChange(of: s.aidChartForecastDisplay) {
                    s.save()
                }
            }.padding()
        }
    }

    var body: some View {
        ScrollView {
            VStack {
                Text("Select CGM").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top)

                GroupBox {
                    ProviderSelection()
                }.padding(.horizontal).padding(.bottom)

                if s.cgmProvider != .null {
                    VStack {
                        Text("\(s.cgmProvider.presentable) Settings", comment: "Settings for CGM providers. For example: Dexcom Share Settings").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.leading)
                        GroupBox {
                            if s.cgmProvider == .simulator {
                                SimulatorView().padding()
                            }

                            if s.cgmProvider == .nightscout {
                                NightscoutView(aidEnabled: s.aidEnableIntegration).padding()
                            }

                            if s.cgmProvider == .dexcomshare {
                                DexcomShareView(s: _s).padding()
                            }

                            if s.cgmProvider == .librelinkup {
                                LibreLinkUpView().padding()
                            }
                        }.padding(.horizontal).padding(.bottom)

                        Validation().padding(.horizontal).padding(.bottom)
                    }
                }
            }
        }
    }
}
