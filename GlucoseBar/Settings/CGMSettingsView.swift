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

    struct TandemSourceView: View {
        @EnvironmentObject var s: SettingsStore

        var body: some View {
            VStack {
                HStack {
                    Text("Email").frame(width: 130, alignment: .leading)
                    Spacer()
                    TextField("", text: $s.tandemEmail).autocorrectionDisabled(true)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("Password").frame(width: 130, alignment: .leading)
                    Spacer()
                    SecureField("", text: $s.tandemPassword).textFieldStyle(RoundedBorderTextFieldStyle())
                }
                HStack {
                    Text("Region").frame(width: 130, alignment: .leading)
                    Spacer()
                    Picker("", selection: $s.tandemRegion) {
                        ForEach(TandemRegion.allCases) { r in
                            Text(r.presentable).tag(r)
                        }
                    }.pickerStyle(SegmentedPickerStyle()).frame(width: 130)
                }
                Text("Your Tandem Source (t:connect) login credentials.").font(.footnote).fixedSize(horizontal: false, vertical: true)
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
        @State var cgmValidationIssue: ProviderIssueKind = .none
        @State var validatedProvider: CGMProvider = .null

        /// Message shown under the Save button when a field can not be used.
        /// Validation owns the Save button, so the reason has to be rendered
        /// here: the `nsSecretFailedValidation` flag this used to set lived in a
        /// sibling view and never reached the screen.
        @State var settingsSaveError: String?

        /// Result copy keyed off the failure classification, so a wrong password
        /// reads differently from a temporary outage.
        private var validationErrorMessage: String {
            switch cgmValidationIssue {
            case .credentials: return String(localized: "Invalid credentials — check the details above")
            case .configuration: return String(localized: "Check the settings above")
            case .apiChange: return String(localized: "This service changed and is temporarily unavailable")
            default: return String(localized: "Service unreachable")
            }
        }

        private var validationErrorIcon: String {
            cgmValidationIssue == .credentials ? "key.slash" : "exclamationmark.triangle"
        }

        /// Validates the fields that both Save and Test Connection depend on,
        /// and normalises the server URL so what gets stored is exactly what was
        /// checked. Returns false (with `settingsSaveError` set) when the user
        /// still has something to fix.
        private func validateFields() -> Bool {
            settingsSaveError = nil

            guard s.cgmProvider == .nightscout else { return true }

            switch ProviderURL.validate(s.nsURL) {
            case .success(let url):
                s.nsURL = url.absoluteString
            case .failure(let invalid):
                settingsSaveError = invalid.message
                return false
            }

            guard s.nsSecret.count > 0 else {
                settingsSaveError = String(localized: "The Token is required for GlucoseBar to function correctly. Please ensure your Nightscout instance has one set up and use it here.", comment: "Validation message shown when the Nightscout token field is left blank")
                return false
            }

            return true
        }

        var body: some View {
            if let providerIssue = g.provider.providerIssue {
                Text("Provider issue: \(providerIssue)").fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if s.cgmProvider != .simulator {
                    Button(action: {
                        isDeletingCGMProvider = true
                    }) {
                        Image(systemName: "trash.fill").foregroundColor(.red)
                    }.disabled(isValidating || ![.nightscout, .dexcomshare, .tandemsource].contains(s.cgmProvider)).help("Delete data for \(s.cgmProvider.presentable)?").confirmationDialog(
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
                        guard validateFields() else { return }

                        isValidating = true
                        Task {
                            validatedProvider = s.cgmProvider
                            g.reset(s)
                            let providerIssue = await s.testCGMProvider()

                            cgmValidationIssue = providerIssue
                            cgmCredentialsError = providerIssue != .none
                            cgmCredentialsSuccess = providerIssue == .none
                            isValidating = false
                            s.validSettings = providerIssue == .none
                        }
                    }) {
                        Text("Test Connection")
                    }.disabled(isValidating)
                }
                if !isValidating && cgmCredentialsError && s.cgmProvider == validatedProvider {
                    HStack {
                        Text(validationErrorMessage).foregroundColor(.orange)
                        Image(systemName: validationErrorIcon).foregroundColor(.orange)
                    }
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
                    guard validateFields() else { return }
                    s.save()
                    g.reset(s)
                }.disabled(isValidating)
            }

            if let settingsSaveError {
                HStack {
                    Text(settingsSaveError).font(.footnote).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }

            // A credential that could not be written to the Keychain has to be said
            // out loud: silently keeping only the old value would look like the save
            // worked.
            if let credentialSaveError = s.credentialSaveError {
                HStack {
                    Text(credentialSaveError).font(.footnote).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
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
                }.frame(width: 200, alignment: .trailing).onChange(of: s.cgmProvider) {
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
                                NightscoutView().padding()
                            }

                            if s.cgmProvider == .dexcomshare {
                                DexcomShareView(s: _s).padding()
                            }

                            if s.cgmProvider == .tandemsource {
                                TandemSourceView().padding()
                            }
                        }.padding(.horizontal).padding(.bottom)

                        Validation().padding(.horizontal).padding(.bottom)
                    }
                }
            }
        }
    }
}
