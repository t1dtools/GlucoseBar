//
//  SettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-01.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var g: Glucose
    @EnvironmentObject var uc: UpdateChecker

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

                    NavigationLink(destination: ChartSettingsView().environmentObject(s)) {
                        Label("Chart", systemImage: "chart.dots.scatter")
                    }.tag("Chart").onTapGesture {
                        selectedItem = "Chart"
                    }

                    if s.aidEnableIntegration && s.cgmProvider == .nightscout {
                        NavigationLink(destination: AidSettingsView().environmentObject(s)) {
                            Label("AID Integration", systemImage: "apps.iphone")
                        }.tag("AID").onTapGesture {
                            selectedItem = "AID"
                        }
                    }

                    NavigationLink(destination: AboutView().environmentObject(s).environmentObject(uc)) {
                        Label("About", systemImage: "info.circle")
                    }.tag("About").onTapGesture {
                        selectedItem = "About"
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
                        if case .outdated(let latestVersion, let latestBuild) = uc.status {
                            Button(action: {
                                NSWorkspace.shared.open(uc.downloadURL)
                            }) {
                                Label("Update available: v\(latestVersion)\(uc.channel == .appStore ? "" : " (\(latestBuild))")", systemImage: "arrow.up.circle.fill")
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(.orange))
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 8)
                        }
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }.padding(.bottom, 10)
//                    }.padding(.horizontal)
                }.frame(alignment: .bottomTrailing).padding(.bottom, 5)
            }
        } detail: {
//            ScrollView {
                GeneralSettingsView().environmentObject(s)
//            }
        }.frame(maxHeight: .infinity, alignment: .top)
            .navigationSplitViewColumnWidth(min: 440, ideal: 440)
            .frame(minWidth: 715, maxWidth: 715, minHeight: 500, maxHeight: .infinity)
    }
}

#Preview {
    SettingsView().environmentObject(SettingsStore()).environmentObject(Glucose(SettingsStore()))
}
