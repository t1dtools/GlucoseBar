//
//  Settings.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-09-25.
//

import Foundation
import OSLog

@MainActor
class SettingsStore: ObservableObject, @unchecked Sendable {

    private let settingsQueue = DispatchQueue(label: "tools.t1d.GlucoseBar.settings", attributes: .concurrent)

    // MARK: - Source identity

    /// The UUID that namespaces all UserDefaults keys for this source.
    let sourceId: UUID

    @Published var sourceName: String = "My CGM"
    @Published var iconSymbol: String = "person.fill"
    @Published var iconColor: CodableColor = .white
    @Published var showSourceIcon: Bool = false

    // MARK: - CGM settings

    @Published var glucoseUnit: GlucoseUnit = .mgdl
    @Published var highThreshold: Double = 180
    @Published var lowThreshold: Double = 70
    @Published var glucoseTarget: Double = 100

    @Published var cgmProvider: CGMProvider = .null
    @Published var graphMinutes: Int = 180

    // Nightscout
    @Published var nsURL: String = "https://my.nightscout.site"
    @Published var nsSecret: String = "my-secret"

    // Dexcom Share
    @Published var dxServer: DexcomServer = .ous
    @Published var dxEmail: String = "your@email.com"
    @Published var dxPassword: String = ""

    // Libre LinkUp
    @Published var libreServer: LibreServer = .eu
    @Published var libreUsername: String = "your@email.com"
    @Published var librePassword: String = ""
    @Published var libreConnectionID: String = ""

    @Published var showTimeSince: Bool = false
    @Published var showDelta: Bool = true

    // MenuBar layout options
    @Published var showMenuBarIcon: Bool = false
    @Published var menuBarItems: [MenuBarItemContainer] = []
    @Published var menuBarItemSpacing: CGFloat = 8.0
    @Published var zenMode: Bool = false

    // Chart settings
    @Published var glucoseColorScheme: GlucoseColorScheme = .dynamicColor
    @Published var showHighThreshold: Bool = true
    @Published var showLowThreshold: Bool = true
    @Published var showTarget: Bool = true

    // Trio / AID Specifics
    @Published var aidEnableIntegration: Bool = false

    @Published var trioBarShowIOB: Bool = false
    @Published var trioBarShowCOB: Bool = false
    @Published var trioBarShowEventualGlucose: Bool = false

    @Published var aidChartShowForecast: Bool = true
    @Published var aidChartForecastDisplay: ForecastDisplay = .lines
    @Published var aidChartShowIOB: Bool = true
    @Published var aidChartShowCOB: Bool = true
    @Published var aidChartShowEventualGlucose: Bool = true
    @Published var aidChartShowLoopStatus: Bool = true

    @Published var validSettings: Bool = false
    @Published var debugMode: Bool = false

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "settingsstore")

    // MARK: - Init

    /// Designated initialiser. All UserDefaults keys are namespaced to `sourceId`
    /// so that multiple sources never collide.
    public init(sourceId: UUID) {
        self.sourceId = sourceId
        load()
        // Re-open the log file if debug mode was already enabled before this launch.
        // This is where file rotation happens: the previous session's debug.log gets
        // archived with a timestamp before a fresh one is opened.
        if debugMode {
            DebugLogger.shared.enable()
        }
    }

    /// Toggles debug mode and starts/stops the file logger accordingly.
    func setDebugMode(_ enabled: Bool) {
        debugMode = enabled
        UserDefaults.standard.set(enabled, forKey: "debugMode")
        if enabled {
            DebugLogger.shared.enable()
        } else {
            DebugLogger.shared.disable()
        }
    }

    /// Convenience initialiser that generates a fresh UUID.
    /// Use for previews, one-off tests, and the throwaway instance inside
    /// `Glucose.init` (which is immediately replaced by `setSettings`).
    public convenience init() {
        self.init(sourceId: UUID())
    }

    // MARK: - Key namespacing

    /// Returns a UserDefaults key namespaced to this source's UUID.
    private func key(_ base: String) -> String {
        "\(sourceId.uuidString).\(base)"
    }

    // MARK: - Load / Save

    func load() {
        settingsQueue.sync {
            loadInternal()
        }
    }

    private func loadInternal() {
        let defaults = UserDefaults.standard

        self.validSettings = defaults.bool(forKey: key("validSettings"))
        self.debugMode = defaults.bool(forKey: "debugMode")

        // Identity
        self.sourceName = defaults.string(forKey: key("sourceName")) ?? "My CGM"
        self.iconSymbol = defaults.string(forKey: key("iconSymbol")) ?? "person.fill"
        self.showSourceIcon = defaults.bool(forKey: key("showSourceIcon"))
        if let data = defaults.data(forKey: key("iconColor")),
           let color = try? JSONDecoder().decode(CodableColor.self, from: data) {
            self.iconColor = color
        } else {
            self.iconColor = .white
        }

        // Nightscout
        self.nsURL = defaults.string(forKey: key("nsURL")) ?? "https://my.nightscout.site"
        self.nsSecret = defaults.string(forKey: key("nsSecret")) ?? ""

        // Dexcom Share
        self.dxEmail = defaults.string(forKey: key("dxEmail")) ?? "your@email.com"
        self.dxPassword = defaults.string(forKey: key("dxPassword")) ?? ""
        let dxSrv = defaults.string(forKey: key("dxServer")) ?? DexcomServer.ous.url
        switch dxSrv {
        case DexcomServer.ous.url:
            self.dxServer = .ous
        case DexcomServer.us.url:
            self.dxServer = .us
        default:
            self.dxServer = .ous
        }

        // Libre LinkUp
        self.libreUsername = defaults.string(forKey: key("libreUsername")) ?? "your@email.com"
        self.librePassword = defaults.string(forKey: key("librePassword")) ?? ""
        self.libreConnectionID = defaults.string(forKey: key("libreConnectionID")) ?? ""
        let libreSrv = defaults.string(forKey: key("libreServer")) ?? LibreServer.eu.url
        self.libreServer = LibreServer.allCases.first(where: { $0.url == libreSrv }) ?? .eu

        self.highThreshold = defaults.double(forKey: key("highThreshold"))
        if (self.highThreshold == 0.0) {
            self.highThreshold = 180
        }

        self.lowThreshold = defaults.double(forKey: key("lowThreshold"))
        if (self.lowThreshold == 0.0) {
            self.lowThreshold = 70
        }

        self.graphMinutes = defaults.integer(forKey: key("graphMinutes"))
        if (self.graphMinutes == 0) {
            self.graphMinutes = 180
        }

        self.showTimeSince = defaults.bool(forKey: key("showTimeSince"))
        self.showDelta = defaults.bool(forKey: key("showDelta"))
        self.showMenuBarIcon = defaults.bool(forKey: key("showMenuBarIcon"))

        let jsonMenuBarItems = defaults.string(forKey: key("menuBarItems"))
        if let jsonMenuBarItems = jsonMenuBarItems {
            let decoder = JSONDecoder()
            if let data = jsonMenuBarItems.data(using: .utf8) {
                do {
                    let decoded = try decoder.decode([MenuBarItemContainer].self, from: data)
                    self.menuBarItems = decoded
                } catch {
                    logger.dlog("Unable to decode menuBarItems object from json saved in UserDefaults: \(String(describing: error))", category: "settingsstore", level: .error)
                    self.menuBarItems = []
                }
            }
        }

        var storedMenuBarItemSpacing = defaults.float(forKey: key("menuBarItemSpacing"))
        if storedMenuBarItemSpacing == 0.0 {
            storedMenuBarItemSpacing = 8.0
        }
        self.menuBarItemSpacing = CGFloat(storedMenuBarItemSpacing)

        self.zenMode = defaults.bool(forKey: key("zenMode"))

        let cgmProv = defaults.string(forKey: key("cgmProvider")) ?? ""
        switch cgmProv {
        case CGMProvider.simulator.presentable:
            self.cgmProvider = .simulator
            self.logger.dlog("cgmProvider was simulator", category: "settingsstore", level: .default)
        case CGMProvider.nightscout.presentable:
            self.cgmProvider = .nightscout
            self.logger.dlog("cgmProvider was nightscout", category: "settingsstore", level: .default)
        case CGMProvider.dexcomshare.presentable:
            self.cgmProvider = .dexcomshare
            self.logger.dlog("cgmProvider was dexcomshare", category: "settingsstore", level: .default)
        case CGMProvider.librelinkup.presentable:
            self.cgmProvider = .librelinkup
            self.logger.dlog("cgmProvider was librelinkup", category: "settingsstore", level: .default)
        default:
            self.cgmProvider = .null
            self.logger.dlog("cgmProvider was default", category: "settingsstore", level: .default)
        }

        let gunit = defaults.string(forKey: key("glucoseUnit")) ?? GlucoseUnit.mmoll.presentable
        switch gunit {
        case GlucoseUnit.mmoll.presentable:
            self.glucoseUnit = .mmoll
        case GlucoseUnit.mgdl.presentable:
            self.glucoseUnit = .mgdl
        default:
            self.glucoseUnit = .mgdl
        }

        self.glucoseTarget = defaults.double(forKey: key("glucoseTarget"))
        if self.glucoseTarget == 0 {
            self.glucoseTarget = 100.0
        }

        let colorScheme = defaults.string(forKey: key("glucoseColorScheme")) ?? GlucoseColorScheme.dynamicColor.displayName
        switch colorScheme {
        case GlucoseColorScheme.staticColor.displayName:
            self.glucoseColorScheme = .staticColor
        case GlucoseColorScheme.dynamicColor.displayName:
            self.glucoseColorScheme = .dynamicColor
        default:
            self.glucoseColorScheme = .dynamicColor
        }

        self.showHighThreshold = defaults.bool(forKey: key("showHighThreshold"))
        self.showLowThreshold = defaults.bool(forKey: key("showLowThreshold"))
        self.showTarget = defaults.bool(forKey: key("showTarget"))

        self.aidEnableIntegration = defaults.bool(forKey: key("trioEnableIntegration"))

        self.trioBarShowIOB = defaults.bool(forKey: key("trioBarShowIOB"))
        self.trioBarShowCOB = defaults.bool(forKey: key("trioBarShowCOB"))
        self.trioBarShowEventualGlucose = defaults.bool(forKey: key("trioBarShowEventualGlucose"))

        self.aidChartShowForecast = defaults.bool(forKey: key("trioChartShowForecast"))
        let forecastDisplay = defaults.string(forKey: key("trioChartForecastDisplay")) ?? ForecastDisplay.lines.presentable
        switch forecastDisplay {
        case ForecastDisplay.lines.presentable:
            self.aidChartForecastDisplay = .lines
        case ForecastDisplay.cone.presentable:
            self.aidChartForecastDisplay = .cone
        default:
            self.aidChartForecastDisplay = .lines
        }

        self.aidChartShowIOB = defaults.bool(forKey: key("trioChartShowIOB"))
        self.aidChartShowCOB = defaults.bool(forKey: key("trioChartShowCOB"))
        self.aidChartShowEventualGlucose = defaults.bool(forKey: key("trioChartShowEventualGlucose"))
        self.aidChartShowLoopStatus = defaults.bool(forKey: key("trioChartShowLoopStatus"))
    }

    func save() {
        settingsQueue.async(flags: .barrier) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.saveInternal()
            }
        }
    }

    private func saveInternal() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: key("validSettings"))
        defaults.set(self.debugMode, forKey: "debugMode")
        defaults.set(self.glucoseUnit.presentable, forKey: key("glucoseUnit"))
        defaults.set(self.cgmProvider.presentable, forKey: key("cgmProvider"))


        defaults.set(self.showTimeSince, forKey: key("showTimeSince"))
        defaults.set(self.showDelta, forKey: key("showDelta"))
        defaults.set(self.showMenuBarIcon, forKey: key("showMenuBarIcon"))

        do {
            let jsonMenuBarItems = try JSONEncoder().encode(self.menuBarItems)
            if let jsonString = String(data: jsonMenuBarItems, encoding: String.Encoding.utf8) {
                defaults.set(jsonString, forKey: key("menuBarItems"))
            } else {
                logger.dlog("Unable to convert encoded menuBarItems object to string", category: "settingsstore", level: .error)
            }

        } catch {
            logger.dlog("failed to encode menuBarItems object: \(String(describing: error))", category: "settingsstore", level: .error)
        }

        defaults.set(self.menuBarItemSpacing, forKey: key("menuBarItemSpacing"))

        defaults.set(self.zenMode, forKey: key("zenMode"))

        defaults.set(self.graphMinutes, forKey: key("graphMinutes"))

        defaults.set(self.highThreshold, forKey: key("highThreshold"))
        defaults.set(self.lowThreshold, forKey: key("lowThreshold"))

        // Nightscout
        defaults.set(self.nsURL, forKey: key("nsURL"))
        defaults.set(self.nsSecret, forKey: key("nsSecret"))

        // Dexcom Share
        defaults.set(self.dxServer.url, forKey: key("dxServer"))
        defaults.set(self.dxEmail, forKey: key("dxEmail"))
        defaults.set(self.dxPassword, forKey: key("dxPassword"))

        // Libre LinkUp
        defaults.set(self.libreServer.url, forKey: key("libreServer"))
        defaults.set(self.libreUsername, forKey: key("libreUsername"))
        defaults.set(self.librePassword, forKey: key("librePassword"))
        defaults.set(self.libreConnectionID, forKey: key("libreConnectionID"))

        defaults.set(self.glucoseTarget, forKey: key("glucoseTarget"))
        defaults.set(self.glucoseColorScheme.displayName, forKey: key("glucoseColorScheme"))
        defaults.set(self.showHighThreshold, forKey: key("showHighThreshold"))
        defaults.set(self.showLowThreshold, forKey: key("showLowThreshold"))
        defaults.set(self.showTarget, forKey: key("showTarget"))

        defaults.set(self.aidEnableIntegration, forKey: key("trioEnableIntegration"))
        defaults.set(self.trioBarShowIOB, forKey: key("trioBarShowIOB"))
        defaults.set(self.trioBarShowCOB, forKey: key("trioBarShowCOB"))
        defaults.set(self.trioBarShowEventualGlucose, forKey: key("trioBarShowEventualGlucose"))
        defaults.set(self.aidChartShowForecast, forKey: key("trioChartShowForecast"))
        defaults.set(self.aidChartForecastDisplay.presentable, forKey: key("trioChartForecastDisplay"))
        defaults.set(self.aidChartShowIOB, forKey: key("trioChartShowIOB"))
        defaults.set(self.aidChartShowCOB, forKey: key("trioChartShowCOB"))
        defaults.set(self.aidChartShowEventualGlucose, forKey: key("trioChartShowEventualGlucose"))
        defaults.set(self.aidChartShowLoopStatus, forKey: key("trioChartShowLoopStatus"))

        // Identity
        defaults.set(self.sourceName, forKey: key("sourceName"))
        defaults.set(self.iconSymbol, forKey: key("iconSymbol"))
        defaults.set(self.showSourceIcon, forKey: key("showSourceIcon"))
        if let data = try? JSONEncoder().encode(self.iconColor) {
            defaults.set(data, forKey: key("iconColor"))
        }

        defaults.synchronize()
        self.loadInternal()
    }

    /// Removes all UserDefaults keys for this source and reloads (returns to
    /// fresh-install defaults). Called by `SourceManager` when the user tries to
    /// delete the last remaining source.
    func resetToDefaults() {
        settingsQueue.async(flags: .barrier) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                let prefix = "\(self.sourceId.uuidString)."
                for k in UserDefaults.standard.dictionaryRepresentation().keys where k.hasPrefix(prefix) {
                    UserDefaults.standard.removeObject(forKey: k)
                }
                self.loadInternal()
            }
        }
    }

    func deleteCGMProvider() {
        settingsQueue.async(flags: .barrier) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.deleteCGMProviderInternal()
            }
        }
    }

    private func deleteCGMProviderInternal() {
        let defaults = UserDefaults.standard

        switch self.cgmProvider {
        case .nightscout:
            self.nsURL = ""
            self.nsSecret = ""
            defaults.removeObject(forKey: key("nsURL"))
            defaults.removeObject(forKey: key("nsSecret"))
        case .dexcomshare:
            self.dxServer = .ous
            self.dxEmail = ""
            self.dxPassword = ""
            defaults.removeObject(forKey: key("dxServer"))
            defaults.removeObject(forKey: key("dxEmail"))
            defaults.removeObject(forKey: key("dxPassword"))
        case .librelinkup:
            self.libreUsername = "your@email.com"
            self.librePassword = ""
            self.libreServer = .eu
            self.libreConnectionID = ""
            defaults.removeObject(forKey: key("libreUsername"))
            defaults.removeObject(forKey: key("librePassword"))
            defaults.removeObject(forKey: key("libreServer"))
            defaults.removeObject(forKey: key("libreConnectionID"))
        default:
            // noop
            return
        }
    }

    func testCGMProvider() async -> Bool {
        var provider: Provider
        self.logger.dlog("testCGMProvider: \(self.cgmProvider.presentable)", category: "settingsstore", level: .default)
        switch self.cgmProvider {
        case .simulator:
            provider = Simulator("test auth")
        case .nightscout:
            provider = Nightscout(baseURL: self.nsURL, token: self.nsSecret, aidEnabled: false)
        case .dexcomshare:
            provider = DexcomShare(username: self.dxEmail, password: self.dxPassword, server: self.dxServer)
        case .librelinkup:
            provider = LibreLinkUp(username: self.libreUsername, password: self.librePassword, server: self.libreServer)
        default:
            provider = Simulator("")
        }

        self.logger.dlog("testCGMProvider calling verifyCredentials with provider: \(provider.type.presentable)", category: "settingsstore", level: .default)
        return await provider.verifyCredentials()
    }

    func resetApplication() async {
        let installID = UserDefaults.standard.string(forKey: "GlucoseBar.installID")
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        if let installID {
            UserDefaults.standard.set(installID, forKey: "GlucoseBar.installID")
        }
        UserDefaults.standard.set(true, forKey: "debugMode")
        restartApp()
    }

    // Found at: https://topscrech.medium.com/how-to-programmatically-restart-a-macos-app-in-swift-91cdb02e0ac0
    private func restartApp() {
        let bundlePath = Bundle.main.bundlePath

        let command = """
        sleep 0.1; open "\(bundlePath)"
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]

        do {
            try task.run()
            exit(0)
        } catch {
            self.logger.dlog("Error restarting app: \(error)", category: "settingsstore", level: .default)
            return
        }
    }

    func disableDebugMode() async -> Bool {
        UserDefaults.standard.set(false, forKey: "debugMode")
        load()
        return true
    }
}

public enum GlucoseUnit: String, CaseIterable, Identifiable, Sendable {
    case mmoll
    case mgdl
    public var id: String { self.rawValue }
    public var presentable: String {
        switch self {
        case .mmoll:
            return "mmol/L"
        case .mgdl:
            return "mg/dL"
        }
    }
}
