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
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .padding()
        .focusEffectDisabled()
    }

    func ZenModeButton() -> some View {
        Button(action: {
            s.zenMode = !s.zenMode
            s.save()
        }) {
            HStack {
                Image(systemName: s.zenMode ? "circle.fill" : "circle").foregroundColor(getDynamicGlucoseColor(glucoseValue: Decimal(g.glucose), highGlucoseColorValue: Decimal(s.highThreshold), lowGlucoseColorValue: Decimal(s.lowThreshold), targetGlucose: Decimal(s.glucoseTarget), glucoseColorScheme: .dynamicColor))
                Text("Zen Mode")
            }
        }
        .keyboardShortcut("z", modifiers: .command)
        .buttonStyle(.plain)
        .padding(4)
        .focusEffectDisabled()
        .padding()

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
                Text("Nightscout")
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

                if let providerIssue = g.provider.providerIssue {
                    Text("Additional Info: \(providerIssue)").fixedSize(horizontal: false, vertical: true).padding(.top)
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
                        ZenModeButton().help("Replaces your configured items in the menu bar with a circle that changes color based on glucose levels.")
                        Spacer()
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
                            Spacer()
                        }.offset(y: -10)
                        Spacer()
                    }
                }
                if g.glucoseTime.timeIntervalSinceNow < -360 {
                    VStack {
                        HStack {
                            Spacer()
                            Label("Stale Glucose: \(g.glucoseAge)", systemImage: "clock.badge.exclamationmark.fill").foregroundColor(.red).padding()
                            Spacer()
                        }.offset(y: -10)
                        Spacer()
                    }
                }
            }
            .frame(width: 500, height: 500, alignment: .leading)
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
        .environmentObject(Glucose(SettingsStore()))
        .environmentObject(SettingsStore())
        .environmentObject(ViewState())
}
