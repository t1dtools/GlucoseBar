//
//  AboutView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-09-09.
//

import SwiftUI
import Awesome

struct AboutView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
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
                }.padding(.top, 5)

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
