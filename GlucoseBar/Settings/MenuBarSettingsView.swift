//
//  MenuBarSettings.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-03.
//

import Foundation
import SwiftUI

struct MenuBarSettingsView: View {
    @EnvironmentObject var s: SettingsStore

    var body: some View {
        ScrollView {
            Text("Menu Bar Settings").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).padding(.top)

            GroupBox {
                VStack {
                    HStack {
                        Text("Show Delta").frame(width: 260, alignment: .leading)
                        Spacer()
                        Toggle(isOn: $s.showDelta, label: {}).toggleStyle(.switch).tint(.blue).fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    Divider()

                    HStack {
                        Text("Always Show Time Since Reading").frame(width: 260, alignment: .leading)
                        Spacer()
                        Toggle(isOn: $s.showTimeSince, label: {}).toggleStyle(.switch).tint(.blue).fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    HStack {
                        Text("Will always show if reading is over 5 minutes old").font(.footnote).foregroundStyle(.gray)
                        Spacer()
                    }
                    Divider()

                    HStack {
                        Text("Enable Icon When Out of Range").frame(width: 260, alignment: .leading)
                        Spacer()
                        Toggle(isOn: $s.showMenuBarIcon, label: {}).toggleStyle(.switch).tint(.blue).fixedSize()
                            .scaleEffect(0.7, anchor: .trailing)
                    }
                    HStack {
                        (
                            Text("Shows a ") +
                            Text(Image(systemName: "drop")) +
                            Text(" when low, a ") +
                            Text(Image(systemName: "drop.fill")) +
                            Text(" when high, and otherwise ") +
                            Text(Image(systemName: "drop.halffull"))
                        ).font(.footnote).foregroundStyle(.gray)
                        Spacer()
                    }
                }.padding()
            }.padding(.horizontal)
        }
    }
}
