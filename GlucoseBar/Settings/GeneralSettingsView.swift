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

    var body: some View {
        ScrollView {
            VStack {
                GroupBox {
                    HStack {
                        if let image = NSImage(named: "AppIcon") {
                            Image(nsImage: image)
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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
            }.padding()
        }
    }
}
