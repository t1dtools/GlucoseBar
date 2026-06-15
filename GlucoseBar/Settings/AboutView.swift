//
//  AboutView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-09-09.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var uc: UpdateChecker

    @ViewBuilder
    var body: some View {
        ScrollView {
            VStack {
                Text("Acknowledgements").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                GroupBox {
                    Group {

                        HStack {
                            Text("These amazing people have helped make GlucoseBar a reality.").frame(alignment: .leading)
                            Spacer()
                        }.padding(.vertical, 3)

                        HStack {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Translations").font(.headline).padding(.bottom, 5)
                                }
                                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                                    GridRow {
                                        Text(verbatim: "Corentin Cras-Méneur")
                                        Text("French")
                                        HStack {
                                            Button(action: {
                                                NSWorkspace.shared.open(URL(string: "https://www.cortig.net/localisations")!)
                                            }) {
                                                HStack {
                                                    Image(systemName: "link")
                                                }
                                            }.buttonStyle(.plain).foregroundStyle(.blue)
                                            Button(action: {
                                                NSWorkspace.shared.open(URL(string: "https://mastodon.social/@cortig")!)
                                            }) {
                                                HStack {
                                                    Text(verbatim: "@cortig")
                                                }
                                            }.buttonStyle(.plain).foregroundStyle(.blue)
                                        }
                                    }
                                    GridRow {
                                        Text(verbatim: "Andreas Stokholm")
                                        Text("Danish, English")
                                        HStack {
                                            Button(action: {
                                                NSWorkspace.shared.open(URL(string: "https://github.com/AndreasStokholm")!)
                                            }) {
                                                HStack {
                                                    Image(systemName: "link")
                                                }
                                            }.buttonStyle(.plain).foregroundStyle(.blue)
                                        }
                                    }
                                }
                            }.padding(.top, 10)
                            Spacer()
                        }

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Developers").font(.headline).padding(.bottom, 5)
                                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                                    GridRow {
                                        Text(verbatim: "Andreas Stokholm")
                                    }
                                }
                                Button(action: {
                                    NSWorkspace.shared.open(URL(string: "https://github.com/t1dtools/GlucoseBar/graphs/contributors")!)
                                }) {
                                    Text("Full list of contributors")
                                }.buttonStyle(.plain).foregroundStyle(.blue).padding(.top, 5)
                            }.padding(.top, 10)
                            Spacer()
                        }.padding(.bottom, 5)
                    }.padding(.leading, 5)
                }

                Text("Get Involved").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                GroupBox {
                    Group {
                        HStack {
                            VStack {
                                Text("We are always looking for help with ideas, bugfixes and translations. If you want to contribute, please see the GitHub respository.").frame(alignment: .leading)
                                Button(action: {
                                    NSWorkspace.shared.open(URL(string: "https://github.com/t1dtools/GlucoseBar#glucosebar")!)
                                }) {
                                    HStack {
                                        Image(systemName: "link")
                                        Text("GitHub")
                                    }
                                }.padding(.vertical, 5)
                            }
                            Spacer()
                        }.padding(.vertical, 3)
                    }.padding(.leading, 5)
                }
            }.padding()
        }
    }
}
