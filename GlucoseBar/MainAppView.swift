//
//  MainAppView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2024-05-02.
//

import Foundation
import SwiftUI
import OSLog

struct MainAppView: View {

    @EnvironmentObject var g: Glucose
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var vs: ViewState

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "main")

    func QuitButton() -> some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            HStack {
                Image(systemName: "xmark.circle")
                Text("Quit")
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding()
        .focusEffectDisabled()
    }

    func SettingsButton() -> some View {
        SettingsLink{
            HStack {
                Image(systemName: "gear")
                Text("Settings")
            }.contentShape(Rectangle())
        }
        .keyboardShortcut(",", modifiers: .command)
        .buttonStyle(.plain)
        .padding()
        .focusEffectDisabled()
    }

    func NightscoutButton() -> some View {
        Button(action: {
            var url = URL(string: s.nsURL)!
            if s.nsSecret != "" {
                url.append(queryItems: [URLQueryItem(name: "token", value: s.nsSecret)])
            }
            if NSWorkspace.shared.open(url) {
                self.logger.debug("opened ns from button action")
            }
        }) {
            HStack {
                Image(systemName: "link")
                Text("Visit Nightscout")
            }.contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .padding()
        .focusEffectDisabled()
    }

    var body: some View {
        if g.error != "" && s.validSettings && vs.isOnline {
            VStack {
                Text("Error").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10).foregroundColor(.red)
                Text("Check the settings and make sure your CGM source (\(s.cgmProvider.presentable)) is responding.").fixedSize(horizontal: false, vertical: true)

                if g.provider.providerIssue != nil {
                    Text("Additional Info: \(g.provider.providerIssue!)").fixedSize(horizontal: false, vertical: true).padding(.top)
                }

                Spacer()
                HStack {
                    SettingsButton()
                    QuitButton()
                }
            }
            .padding()
            .frame(width: 300, height: 200, alignment: .leading)
            .focusable()
            .focusEffectDisabled()
//            .onKeyPress(keys: [.escape]) { press in
//                DispatchQueue.main.async {
//                    vs.isPanePresented = false
//                }
//                return .handled
//            }
        } else if (s.validSettings) {
            ZStack {
                VStack {
                    GraphView(glucose: g).environmentObject(s).environmentObject(vs)
                    HStack {
                        if s.cgmProvider == .nightscout {
                            NightscoutButton()
                        }
                        SettingsButton()
                        QuitButton()
                    }
                }
                if !vs.isOnline {
                    VStack {
                        HStack {
                            Spacer()
                            Label("Offline", systemImage: "bolt.horizontal").foregroundColor(.red).padding()
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 500, height: s.hoverableGraph ? 500 : 400, alignment: .leading)
            .focusable()
            .focusEffectDisabled()
//            .onKeyPress(keys: [.escape]) { press in
//                DispatchQueue.main.async {
//                    vs.isPanePresented = false
//                }
//                return .handled
//            }
        } else {
            WelcomeView().frame(width: 400, height: 390, alignment: .leading)
//            VStack {
//                Text("Welcome to GlucoseBar!\n\nUse this application to keep your glucose glanceable in your menu bar at all times.\n\nGet started by configuring GlucoseBar.")
//
//                SettingsButton()
//                QuitButton()
//            }
            .padding()
            .focusable()
            .focusEffectDisabled()
//            .onKeyPress(keys: [.escape]) { press in
//                DispatchQueue.main.async {
//                    vs.isPanePresented = false
//                }
//                return .handled
//            }
        }
    }
}

#Preview {
    MainAppView()
        .environmentObject(Glucose())
        .environmentObject(SettingsStore())
        .environmentObject(ViewState())
}
