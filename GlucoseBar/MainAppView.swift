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
    @EnvironmentObject var uc: UpdateChecker

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
                self.logger.dlog("opened ns from button action", category: "main", level: .default)
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
            if g.provider.providerIssue == DexcomShare.noDataIssue {
                ScrollView {
                    Image(systemName: "bolt.trianglebadge.exclamationmark").resizable()
                        .frame(width: 96, height: 96).foregroundColor(.red).padding(.top, 5).padding(.horizontal)
                    Text("No data from Dexcom. Please ensure your Dexcom Share connection is functional on your phone.").fixedSize(horizontal: false, vertical: true).foregroundColor(.red).padding(.horizontal)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Please ensure the following:").font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text("- You have enabled Dexcom Share and have at least one follower.").fixedSize(horizontal: false, vertical: true)
                        Text("- You are logged into GlucoseBar with the same user as in your primary Dexcom app.").fixedSize(horizontal: false, vertical: true)
                        Text("- Verify that your Dexcom app isn't logged out or not uploading to Dexcom.").fixedSize(horizontal: false, vertical: true)
                        Text("- Try turning Dexcom Share off in the Dexcom G6 or G7 app, force close the app, and then enabling it again.").fixedSize(horizontal: false, vertical: true)
                    }.padding()
                    VStack {
                        Text("If you are still having issues, please post a detailed issue on GitHub.").padding()
                        Button(action: {
                            NSWorkspace.shared.open(URL(string: "https://github.com/t1dtools/GlucoseBar/issues?q=sort%3Aupdated-desc%20state%3Aopen%20label%3Adexcom-no-data")!)
                        }) {
                            Text("Open GitHub Issue")
                        }.padding(.horizontal)
                        HStack {
                            Spacer()
                            SettingsButton()
                        }
                    }
                }.padding()
                    .frame(width: 500, height: 525, alignment: .leading)
                    .focusable()
                    .focusEffectDisabled()
            } else {
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
            }
//            .onKeyPress(keys: [.escape]) { press in
//                DispatchQueue.main.async {
//                    vs.isPanePresented = false
//                }
//                return .handled
//            }
        } else if (s.validSettings) {
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: s.iconSymbol).foregroundStyle(s.iconColor.color)
                        Text(s.sourceName).font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal).padding(.top, 8)
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
                if case .outdated(let latestVersion, let latestBuild) = uc.status {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(uc.downloadURL)
                            }) {
                                Label("Update available: v\(latestVersion)\(uc.channel == .appStore ? "" : " (\(latestBuild))")", systemImage: "arrow.up.circle.fill")
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(.plain)
                            .focusEffectDisabled()
                            .padding()
                            .help("A new version of GlucoseBar is available.")
                        }.offset(y: -10)
                        Spacer()
                    }
                } else if !vs.isOnline {
                    VStack {
                        HStack {
                            Spacer()
                            Label("Offline", systemImage: "bolt.horizontal").foregroundColor(.red).padding()
                            Spacer()
                        }.offset(y: -10)
                        Spacer()
                    }
                } else if g.glucoseTime.timeIntervalSinceNow < -360 {
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
        .environmentObject(UpdateChecker())
}
