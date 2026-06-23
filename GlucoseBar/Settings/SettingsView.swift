//
//  SettingsView.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-10-01.
//

import Foundation
import SwiftUI

// MARK: - Navigation enums

private enum SidebarItem: Hashable {
    case general
    case debug
    case about
    case sourceIdentity(UUID)
    case sourceCGM(UUID)
    case sourceMenuBar(UUID)
    case sourceThresholds(UUID)
    case sourceAID(UUID)
    case sourceChart(UUID)
}

// MARK: - SourceSidebarSection

/// One source's sidebar section: a header with icon + name and 4–5 sub-items.
///
/// Uses `@ObservedObject var settings` so the header and the conditional AID row
/// update immediately when the user changes the source name or icon.
private struct SourceSidebarSection: View {
    @ObservedObject var settings: SettingsStore
    let sourceId: UUID

    init(settings: SettingsStore, sourceId: UUID) {
        self.settings = settings
        self.sourceId = sourceId
    }

    var body: some View {
        Section {
            Label("Identity", systemImage: "person.crop.circle")
                .tag(SidebarItem.sourceIdentity(sourceId))
            Label("CGM", systemImage: "bandage.fill")
                .tag(SidebarItem.sourceCGM(sourceId))
            Label("Menu Bar", systemImage: "menubar.rectangle")
                .tag(SidebarItem.sourceMenuBar(sourceId))
            Label("Chart", systemImage: "chart.dots.scatter")
                .tag(SidebarItem.sourceChart(sourceId))
            Label("Thresholds & Display", systemImage: "gear")
                .tag(SidebarItem.sourceThresholds(sourceId))
            if settings.aidEnableIntegration && settings.cgmProvider == .nightscout {
                Label("AID Integration", systemImage: "apps.iphone")
                    .tag(SidebarItem.sourceAID(sourceId))
            }
        }
    }
}

// MARK: - SourcePickerLabel

private struct SourcePickerLabel: View {
    @ObservedObject var settings: SettingsStore
    var body: some View { Text(settings.sourceName) }
}

// MARK: - SettingsView

struct SettingsView: View {
    @EnvironmentObject var sourceManager: SourceManager
    @EnvironmentObject var uc: UpdateChecker

    @State private var selectedItem: SidebarItem? = nil
    @State private var selectedSource: SourceState?
    @State private var didAppear = false

    init(sourceManager: SourceManager) {
        _selectedSource = State(initialValue: sourceManager.sources.first)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            VStack {
                List(selection: $selectedItem) {

                    Section {
                        Label("General", systemImage: "gear")
                            .tag(SidebarItem.general)
                        if sourceManager.sources.first?.settings.debugMode == true {
                            Label("Debug", systemImage: "ladybug.fill")
                                .tag(SidebarItem.debug)
                        }
                        Label("About", systemImage: "info.circle")
                            .tag(SidebarItem.about)
                    }

                    Divider()

                    VStack {
                        HStack {
                            Label("Profiles", systemImage: "person.2.fill")
                                .font(.headline)
                                .frame(maxWidth: 200, alignment: .leading)
                            Spacer()

                            let atLimit = sourceManager.sources.count >= SourceManager.maxSources
                            if !atLimit {
                                Button("+") {
                                    let newSourceID = sourceManager.addSource()
                                    selectedSource = sourceManager.sources.first(where: { $0.id == newSourceID })
                                }
                            }

                            if atLimit {
                                Text("\(SourceManager.maxSources) max", comment: "A message shown in the settings sidebar when the maximum number of profiles has been reached")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.bottom, 4)
                            }
                        }

                        let picker = Picker("", selection: $selectedSource) {
                            ForEach(sourceManager.sources) { source in
                                SourcePickerLabel(settings: source.settings)
                                    .tag(source as SourceState?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 165)

                        Group {
                            if #available(macOS 26.0, *) {
                                AnyView(picker.buttonSizing(.flexible))
                            } else {
                                AnyView(picker)
                            }
                        }
                        .onChange(of: selectedSource) { _, newSource in
                            guard didAppear, let source = newSource else { return }
                            selectedItem = .sourceIdentity(source.id)
                        }
                        .onChange(of: selectedItem) { _, item in
                            switch item {
                            case .sourceIdentity(let id):
                                selectedSource = sourceManager.sources.first(where: { $0.id == id })
                            case .sourceCGM(let id):
                                selectedSource = sourceManager.sources.first(where: { $0.id == id })
                            case .sourceMenuBar(let id):
                                selectedSource = sourceManager.sources.first(where: { $0.id == id })
                            case .sourceThresholds(let id):
                                selectedSource = sourceManager.sources.first(where: { $0.id == id })
                            case .sourceAID(let id):
                                selectedSource = sourceManager.sources.first(where: { $0.id == id })
                            case .sourceChart(let id):
                                selectedSource = sourceManager.sources.first(where: { $0.id == id })
                            case .none, .general, .debug, .about:
                                break
                            }
                        }
                    }

                    let source = selectedSource ?? sourceManager.sources.first!
                    SourceSidebarSection(
                        settings: source.settings,
                        sourceId: source.id
                    )
                }
                .toolbar(removing: .sidebarToggle)
                .listStyle(.sidebar)
                .frame(width: 200)
                .padding(.top, 10)

                Group {
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

                    Divider()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }.padding(.bottom, 10)
                }
                .frame(alignment: .bottomTrailing)
                .padding(.bottom, 5)
            }
        } detail: {
            detailView
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationSplitViewColumnWidth(min: 440, ideal: 440)
        .frame(minWidth: 715, maxWidth: 715, minHeight: 500, maxHeight: .infinity)
        .onAppear {
            selectedSource = sourceManager.sources.first
            selectedItem = .general
            didAppear = true
        }
        .onChange(of: sourceManager.sources.count) {
            if let sel = selectedSource, !sourceManager.sources.contains(where: { $0.id == sel.id }) {
                selectedSource = sourceManager.sources.first
            }

            guard let item = selectedItem else { return }
            let sourceId: UUID?
            switch item {
            case .sourceIdentity(let id):   sourceId = id
            case .sourceCGM(let id):        sourceId = id
            case .sourceMenuBar(let id):    sourceId = id
            case .sourceThresholds(let id): sourceId = id
            case .sourceAID(let id):        sourceId = id
            case .sourceChart(let id):      sourceId = id
            case .general, .debug, .about:  sourceId = nil
            }
            guard let id = sourceId else { return }
            if !sourceManager.sources.contains(where: { $0.id == id }) {
                selectedItem = sourceManager.sources.first.map { .sourceThresholds($0.id) }
            }
        }
    }

    // MARK: - Detail view

    @ViewBuilder
    private var detailView: some View {
        if let item = selectedItem {
            switch item {
            case .sourceIdentity(let id):
                sourceView(id: id) { source in
                    SourceIdentityView()
                        .environmentObject(source.settings)
                }
            case .sourceCGM(let id):
                sourceView(id: id) { source in
                    CGMSettingsView()
                        .environmentObject(source.settings)
                        .environmentObject(source.glucose)
                }
            case .sourceMenuBar(let id):
                sourceView(id: id) { source in
                    MenuBarSettingsView()
                        .environmentObject(source.settings)
                        .environmentObject(source.glucose)
                }
            case .sourceThresholds(let id):
                sourceView(id: id) { source in
                    GlucoseThresholdsView()
                        .environmentObject(source.settings)
                        .environmentObject(source.glucose)
                }
            case .sourceAID(let id):
                sourceView(id: id) { source in
                    AidSettingsView()
                        .environmentObject(source.settings)
                        .environmentObject(source.glucose)
                }
            case .sourceChart(let id):
                sourceView(id: id) { source in
                    ChartSettingsView()
                        .environmentObject(source.settings)
                        .environmentObject(source.glucose)
                }
            case .general:
                GeneralSettingsView()
                    .environmentObject(uc)
            case .debug:
                if let source = sourceManager.sources.first {
                    DebugSettingsView()
                        .environmentObject(source.settings)
                }
            case .about:
                AboutView()
            }
        } else {
            if let source = sourceManager.sources.first {
                GeneralSettingsView()
                    .environmentObject(source.settings)
            }
        }
    }

    /// Looks up a `SourceState` by id and passes it to `content`, or shows
    /// a "profile not found" placeholder if the id is stale.
    @ViewBuilder
    private func sourceView<Content: View>(
        id: UUID,
        @ViewBuilder content: (SourceState) -> Content
    ) -> some View {
        if let source = sourceManager.sources.first(where: { $0.id == id }) {
            content(source)
        } else {
            Text("Profile not found.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - SourceIdentityView

private struct SourceIdentityView: View {
    @EnvironmentObject var s: SettingsStore
    @EnvironmentObject var sourceManager: SourceManager

    @State private var showRemoveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                Text("Profile Identity")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                GroupBox {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Name")
                                .frame(width: 160, alignment: .leading)
                            Spacer()
                            TextField("My CGM", text: $s.sourceName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: s.sourceName) { s.save() }
                        }
                        .padding(.vertical, 6)

                        Divider()

                        HStack {
                            Text("Show icon in menu bar")
                                .frame(width: 160, alignment: .leading)
                            Spacer()
                            Toggle("", isOn: $s.showSourceIcon)
                                .toggleStyle(.switch)
                                .tint(.blue)
                                .fixedSize()
                                .scaleEffect(0.7, anchor: .trailing)
                                .onChange(of: s.showSourceIcon) { s.save() }
                        }
                        .padding(.vertical, 6)
                    }
                    .padding()
                }

                Text("Icon")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                GroupBox {
                    SymbolPickerView()
                        .padding()
                }

                if sourceManager.sources.count > 1 {
                    Divider()
                        .padding(.top, 24)
                        .padding(.bottom, 16)

                    Button(role: .destructive) {
                        showRemoveConfirmation = true
                    } label: {
                        Label("Remove Profile", systemImage: "trash")
                    }
                    .confirmationDialog(
                        "Remove \"\(s.sourceName)\"?",
                        isPresented: $showRemoveConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Remove Profile", role: .destructive) {
                            if let source = sourceManager.sources.first(where: { $0.settings === s }) {
                                sourceManager.removeSource(id: source.id)
                            }
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("All settings for this profile will be deleted and cannot be recovered.")
                    }
                }
            }
            .padding()
        }
    }
}

#Preview {
    let sm = SourceManager()
    SettingsView(sourceManager: sm)
        .environmentObject(sm)
        .environmentObject(UpdateChecker())
}
