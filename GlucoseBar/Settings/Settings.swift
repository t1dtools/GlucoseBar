//
//  Settings.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2023-09-25.
//

import Foundation
import OSLog

class SettingsStore: ObservableObject, @unchecked Sendable {

    @Published var glucoseUnit: GlucoseUnit = .mgdl
    @Published var highThreshold: Double = 180
    @Published var lowThreshold: Double = 70
    @Published var glucoseTarget: Double = 100
    @Published var glucoseColorScheme: GlucoseColorScheme = .dynamicColor

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
    @Published var libreServer: String = ""
    @Published var libreUsername: String = "your@email.com"
    @Published var librePassword: String = ""
    @Published var libreConnectionID: String = ""

    @Published var showTimeSince: Bool = false
    @Published var showDelta: Bool = true

    // MenuBar layout options
    @Published var showMenuBarIcon: Bool = false
    @Published var menuBarItems: [MenuBarItemContainer] = []

    // Trio Specifics
    @Published var trioBarShowIOB: Bool = false
    @Published var trioBarShowCOB: Bool = false
    @Published var trioBarShowEventualGlucose: Bool = false

    @Published var trioChartShowForecast: Bool = true
    @Published var trioChartForecastDisplay: ForecastDisplay = .lines
    @Published var trioChartShowIOB: Bool = true
    @Published var trioChartShowCOB: Bool = true
    @Published var trioChartShowEventualGlucose: Bool = true
    @Published var trioChartShowLoopStatus: Bool = true

    @Published var validSettings: Bool = false

    let logger = Logger(subsystem: "tools.t1d.GlucoseBar", category: "settingsstore")

    public init() {
        load()
    }

    func load() {

        let defaults = UserDefaults.standard

        self.validSettings = defaults.bool(forKey: "validSettings")

        // Nightscout
        self.nsURL = defaults.string(forKey: "nsURL") ?? "https://my.nightscout.site"
        self.nsSecret = defaults.string(forKey: "nsSecret") ?? ""

        // Dexcom Share
        self.dxEmail = defaults.string(forKey: "dxEmail") ?? "your@email.com"
        self.dxPassword = defaults.string(forKey: "dxPassword") ?? ""
        let dxSrv = defaults.string(forKey: "dxServer") ?? DexcomServer.ous.url
        switch dxSrv {
        case DexcomServer.ous.url:
            self.dxServer = .ous
        case DexcomServer.us.url:
            self.dxServer = .us
        default:
            self.dxServer = .ous
        }

        // Libre LinkUp
        self.libreUsername = defaults.string(forKey: "libreUsername") ?? "your@email.com"
        self.librePassword = defaults.string(forKey: "librePassword") ?? ""
        self.libreConnectionID = defaults.string(forKey: "libreConnectionID") ?? ""
        self.libreServer = defaults.string(forKey: "libreServer") ?? ""

        self.highThreshold = defaults.double(forKey: "highThreshold")
        if (self.highThreshold == 0.0) {
            self.highThreshold = 180
        }

        self.lowThreshold = defaults.double(forKey: "lowThreshold")
        if (self.lowThreshold == 0.0) {
            self.lowThreshold = 70
        }

        self.graphMinutes = defaults.integer(forKey: "graphMinutes")
        if (self.graphMinutes == 0) {
            self.graphMinutes = 180
        }

        self.showTimeSince = defaults.bool(forKey: "showTimeSince")
        self.showDelta = defaults.bool(forKey: "showDelta")
        self.showMenuBarIcon = defaults.bool(forKey: "showMenuBarIcon")

//        defaults.removeObject(forKey: "menuBarItems")

        let jsonMenuBarItems = defaults.string(forKey: "menuBarItems")
        if let jsonMenuBarItems = jsonMenuBarItems {
            let decoder = JSONDecoder()
            if let data = jsonMenuBarItems.data(using: .utf8) {
                do {
                    let decoded = try decoder.decode([MenuBarItemContainer].self, from: data)
                    self.menuBarItems = decoded
                } catch {
                    logger.error("Unable to decode menuBarItems object from json saved in UserDefaults: \(String(describing: error))")
                    self.menuBarItems = []
                }
            }
        }

        let cgmProv = defaults.string(forKey: "cgmProvider") ?? ""
        switch cgmProv {
        case "":
            self.cgmProvider = .simulator
            self.logger.debug("cgmProvider was '' (empty)")
        case CGMProvider.simulator.presentable:
            self.cgmProvider = .simulator
            self.logger.debug("cgmProvider was simulator")
        case CGMProvider.nightscout.presentable:
            self.cgmProvider = .nightscout
            self.logger.debug("cgmProvider was nightscout")
        case CGMProvider.dexcomshare.presentable:
            self.cgmProvider = .dexcomshare
            self.logger.debug("cgmProvider was dexcomshare")
        case CGMProvider.librelinkup.presentable:
            self.cgmProvider = .librelinkup
            self.logger.debug("cgmProvider was librelinkup")
        default:
            self.cgmProvider = .null
            self.logger.debug("cgmProvider was default")
        }

        let gunit = defaults.string(forKey: "glucoseUnit") ?? GlucoseUnit.mmoll.presentable
        switch gunit {
        case GlucoseUnit.mmoll.presentable:
            DispatchQueue.main.async {
                self.glucoseUnit = .mmoll
            }
        case GlucoseUnit.mgdl.presentable:
            DispatchQueue.main.async {
                self.glucoseUnit = .mgdl
            }
        default:
            DispatchQueue.main.async {
                self.glucoseUnit = .mgdl
            }
        }
        
        self.glucoseTarget = defaults.double(forKey: "glucoseTarget")
        if self.glucoseTarget == 0 {
            self.glucoseTarget = 100.0
        }
        let colorScheme = defaults.string(forKey: "glucoseColorScheme") ?? GlucoseColorScheme.staticColor.displayName
        switch colorScheme {
        case GlucoseColorScheme.staticColor.displayName:
            DispatchQueue.main.async {
                self.glucoseColorScheme = .staticColor
            }
        case GlucoseColorScheme.dynamicColor.displayName:
            DispatchQueue.main.async {
                self.glucoseColorScheme = .dynamicColor
            }
        default:
            DispatchQueue.main.async {
                self.glucoseColorScheme = .dynamicColor
            }
        }

        self.trioBarShowIOB = defaults.bool(forKey: "trioBarShowIOB")
        self.trioBarShowCOB = defaults.bool(forKey: "trioBarShowCOB")
        self.trioBarShowEventualGlucose = defaults.bool(forKey: "trioBarShowEventualGlucose")

        self.trioChartShowForecast = defaults.bool(forKey: "trioChartShowForecast")
        let forecastDisplay = defaults.string(forKey: "trioChartForecastDisplay") ?? ForecastDisplay.lines.presentable
        switch forecastDisplay {
        case ForecastDisplay.lines.presentable:
            DispatchQueue.main.async {
                self.trioChartForecastDisplay = .lines
            }
        case ForecastDisplay.cone.presentable:
            DispatchQueue.main.async {
                self.trioChartForecastDisplay = .cone
            }
        default:
            DispatchQueue.main.async {
                self.trioChartForecastDisplay = .lines
            }
        }

        self.trioChartShowIOB = defaults.bool(forKey: "trioChartShowIOB")
        self.trioChartShowCOB = defaults.bool(forKey: "trioChartShowCOB")
        self.trioChartShowEventualGlucose = defaults.bool(forKey: "trioChartShowEventualGlucose")
        self.trioChartShowLoopStatus = defaults.bool(forKey: "trioChartShowLoopStatus")
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "validSettings")
        defaults.set(self.glucoseUnit.presentable, forKey: "glucoseUnit")
        defaults.set(self.cgmProvider.presentable, forKey: "cgmProvider")

        defaults.set(self.showTimeSince, forKey: "showTimeSince")
        defaults.set(self.showDelta, forKey: "showDelta")
        defaults.set(self.showMenuBarIcon, forKey: "showMenuBarIcon")

        do {
            let jsonMenuBarItems = try JSONEncoder().encode(self.menuBarItems)
            if let jsonString = String(data: jsonMenuBarItems, encoding: String.Encoding.utf8) {
                defaults.set(jsonString, forKey: "menuBarItems")
            } else {
                logger.error("Unable to convert encoded menuBarItems object to string")
            }
        } catch {
            logger.error("failed to encode menuBarItems object: \(error.localizedDescription)")
        }

        defaults.set(self.graphMinutes, forKey: "graphMinutes")

        defaults.set(self.highThreshold, forKey: "highThreshold")
        defaults.set(self.lowThreshold, forKey: "lowThreshold")

        // Nightscout
        defaults.set(self.nsURL, forKey: "nsURL")
        defaults.set(self.nsSecret, forKey: "nsSecret")

        // Dexcom Share
        defaults.set(self.dxServer.url, forKey: "dxServer")
        defaults.set(self.dxEmail, forKey: "dxEmail")
        defaults.set(self.dxPassword, forKey: "dxPassword")

        // Libre LinkUp
        defaults.set(self.libreServer, forKey: "libreServer")
        defaults.set(self.libreUsername, forKey: "libreUsername")
        defaults.set(self.librePassword, forKey: "librePassword")
        defaults.set(self.libreConnectionID, forKey: "libreConnectionID")

        defaults.set(self.glucoseTarget, forKey: "glucoseTarget")
        defaults.set(self.glucoseColorScheme.displayName, forKey: "glucoseColorScheme")

        defaults.set(self.trioBarShowIOB, forKey: "trioBarShowIOB")
        defaults.set(self.trioBarShowCOB, forKey: "trioBarShowCOB")
        defaults.set(self.trioBarShowEventualGlucose, forKey: "trioBarShowEventualGlucose")
        defaults.set(self.trioChartShowForecast, forKey: "trioChartShowForecast")
        defaults.set(self.trioChartForecastDisplay.presentable, forKey: "trioChartForecastDisplay")
        defaults.set(self.trioChartShowIOB, forKey: "trioChartShowIOB")
        defaults.set(self.trioChartShowCOB, forKey: "trioChartShowCOB")
        defaults.set(self.trioChartShowEventualGlucose, forKey: "trioChartShowEventualGlucose")
        defaults.set(self.trioChartShowLoopStatus, forKey: "trioChartShowLoopStatus")
    }

    func deleteCGMProvider() {
        let defaults = UserDefaults.standard

        switch self.cgmProvider {
        case .nightscout:
            self.nsURL = ""
            self.nsSecret = ""
            defaults.removeObject(forKey: "nsURL")
            defaults.removeObject(forKey: "nsSecret")
        case .dexcomshare:
            self.dxServer = .ous
            self.dxEmail = ""
            self.dxPassword = ""
            defaults.removeObject(forKey: "dxServer")
            defaults.removeObject(forKey: "dxEmail")
            defaults.removeObject(forKey: "dxPassword")
        default:
            // noop
            return
        }
    }

    func testCGMProvider() async -> Bool {
        self.logger.debug("testCGMProvider")

        var provider: Provider
        switch self.cgmProvider {
        case .simulator:
            self.logger.debug("testCGMProvider.simulator")
            provider = Simulator("test auth")
        case .nightscout:
            self.logger.debug("testCGMProvider.nightscout")
            provider = Nightscout(baseURL: self.nsURL, token: self.nsSecret)
        case .dexcomshare:
            self.logger.debug("testCGMProvider.dexcomshare")
            provider = DexcomShare(username: self.dxEmail, password: self.dxPassword, server: self.dxServer)
//        case .librelinkup:
//            self.logger.debug("testCGMProvider.librelinkup")
//            provider = LibreLinkUp(username: self.libreUsername, password: self.librePassword)
        default:
            self.logger.debug("testCGMProvider.simulator")
            provider = Simulator("")
        }

        self.logger.debug("testCGMProvider calling verifyCredentials with provider: \(provider.type.presentable)")
        return await provider.verifyCredentials()
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
