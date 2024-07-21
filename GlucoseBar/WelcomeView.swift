//
//  WelcomeView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2024-05-11.
//

import Foundation
import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {

            HStack {
                Spacer()
                if let image = NSImage(named: "AppIcon") {
                    Image(nsImage: image)

                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text("Hi,\nI'm GlucoseBar.").font(.title).multilineTextAlignment(.center)
                Spacer()
            }.padding()


            Text("I'm a privacy first application that lives in here the menu bar on your Mac, providing you a quick way to glance at your Continous Glucose Monitor (CGM) readings, from places like Nightscout and Dexcom").multilineTextAlignment(.center)

            Spacer()
            Text("Since this is the first time we meet, you need to help me access your Glucose data. Head over to \(Image(systemName:"gear")) Settings to get started.").multilineTextAlignment(.center)

            HStack {
                SettingsLink{
                    HStack {
                        Image(systemName: "gear")
                        Text("Settings")
                    }.contentShape(Rectangle())
                }
                .keyboardShortcut(",", modifiers: .command)
                .focusEffectDisabled()
            }.padding(.vertical)
        }.padding()
    }
}

#Preview {
    WelcomeView()
}
