//
//  SettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-01.
//

import Foundation
import SwiftUI
import LaunchAtLogin
import OSLog

struct SettingsView: View {
    
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose

    internal var logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "settingsview")

    @State var selectedItem: String = "General"

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            VStack {
                List(selection: $selectedItem) {
                    NavigationLink(destination: GeneralSettingsView().environmentObject(s)) {
                        Label("General", systemImage: "gear")
                    }.tag("General").onTapGesture {
                        selectedItem = "General"
                    }

                    NavigationLink(destination: CGMSettingsView().environmentObject(s)) {
                        Label("CGM", systemImage: "bandage.fill")
                    }.tag("CGM").onTapGesture {
                        selectedItem = "CGM"
                    }

                    NavigationLink(destination: MenuBarSettingsView().environmentObject(s)) {
                        Label("Menu Bar", systemImage: "menubar.rectangle")
                    }.tag("MenuBar").onTapGesture {
                        selectedItem = "MenuBar"
                    }

                    if g.provider.RemoteGlucoseSource == .trio {
                        NavigationLink(destination: TrioSettingsView().environmentObject(s)) {
                            Label("Trio Integration", systemImage: "apps.iphone")
                        }.tag("Trio").onTapGesture {
                            selectedItem = "Trio"
                        }
                    }
                }
                .toolbar(removing: .sidebarToggle)
                .listStyle(.sidebar)
                .frame(width: 200)
                .padding(.top, 10)

                Group {
//                    HStack {
//                        ShareLink(item: URL(string: "https://apps.apple.com/app/glucosebar/id6468110131")!, subject: Text(""), message: Text(""))
//                        Spacer()
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
//                    }.padding(.horizontal)
                    Text("\(Bundle.main.appName) Version: \(Bundle.main.appVersionLong) (\(Bundle.main.appBuild)) ").font(.footnote).padding(2)
                }.frame(alignment: .bottomTrailing).padding(.bottom, 5)
            }
        } detail: {
            ScrollView {
//                MenuBarSettingsView().environmentObject(s)
                GeneralSettingsView().environmentObject(s)
            }
        }.frame(maxHeight: .infinity, alignment: .top)
            .navigationSplitViewColumnWidth(min: 440, ideal: 440)
            .frame(minWidth: 715, maxWidth: 715, minHeight: 500, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView().environmentObject(SettingsStore()).environmentObject(Glucose())
}
