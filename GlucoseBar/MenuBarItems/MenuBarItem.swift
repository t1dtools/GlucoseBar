//
//  MenuBarItem.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-16.
//

import Combine
import SwiftUI

public enum MenuBarItem: String, CaseIterable, Identifiable, Sendable, Codable {
    case glucosevalue
    case glucosetrend
    case glucosedelta
    case glucosedot
    case loopstatus
    case eventualglucose
    case iob
    case cob
    case separator
    public var id: String { self.rawValue }
    public var name: String {
        switch self {
        case .glucosevalue:
            return String(localized: "Glucose Value", comment: "The name of the Glucose Value menu bar item")
        case .glucosetrend:
            return String(localized: "Glucose Trend", comment: "The name of the Glucose Trend menu bar item")
        case .glucosedelta:
            return String(localized: "Glucose Delta", comment: "The name of the Glucose Delta menu bar item")
        case .glucosedot:
            return String(localized: "Glucose Dot", comment: "The name of the Glucose Dot menu bar item")

        // Trio
        case .loopstatus:
            return String(localized: "Loop Status", comment: "The name of the Loop Status menu bar item")
        case .eventualglucose:
            return String(localized: "Eventual Glucose", comment: "The name of the Eventual Glucose menu bar item")
        case .iob:
            return String(localized: "Insulin On Board", comment: "The name of the Insulin On Board menu bar item")
        case .cob:
            return String(localized: "Carbs On Board", comment: "The name of the Carbs on Board menu bar item")

        // Separator
        case .separator:
            return String(localized: "Separator", comment: "The name of the Separator menu bar item")

        }
    }
}

public enum settingKey: String, CaseIterable, Codable, Sendable {
    case textColor
    case fontWeight
    case icon
    case iconPlacement
    case displayTextAndIcon
    case character
    case hideZero
}

public enum settingValue: String, CaseIterable, Codable, Sendable {

    // Display
    case displayBoth
    case displayText
    case displayIcon

    case hideZeroTrue
    case hideZeroFalse

    // Text
    case textColorDefault
    case textColorStaticGlucose
    case textColorDynamicGlucose

    case fontWeightRegular
    case fontWeightLight
    case fontWeightBold

    // Icons
    case iconColorHidden
    case iconColorSingle
    case iconColorStaticGlucose
    case iconColorDynamicGlucose
    case iconColorBlue
    case iconColorOrange

    case iconPlacementLeading
    case iconPlacementTrailing

    // Separators
    case separatorCharPipe
    case separatorCharDash
    case separatorCharDot
    case separatorCharSlash
    case separatorCharBackslash

    // None
    case none
}

public struct MenuBarItemSetting: Codable {
    var key: settingKey
    var value: settingValue
}

public class MenuBarItemContainer: Equatable, Identifiable, Hashable, Codable, ObservableObject {
    public var type: MenuBarItem
    @Published public var settings: [MenuBarItemSetting]

    private enum CodingKeys : String, CodingKey {
        case type = "type"
        case settings = "settings"
    }

    required public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(MenuBarItem.self, forKey: .type)
        do {
            let decoded = try container.decode([MenuBarItemSetting].self, forKey: .settings)
            self.settings = decoded
        } catch {
            self.settings = []
        }
    }

    init(type: MenuBarItem) {
        self.type = type

        switch type {
        case .glucosevalue:
            self.settings = [
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
                MenuBarItemSetting(key: .icon, value: .iconColorHidden),
                MenuBarItemSetting(key: .iconPlacement, value: .iconPlacementLeading),
            ]
        case .glucosedelta:
            self.settings = [
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
            ]
        case .glucosetrend:
            self.settings = [
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
            ]
        case .glucosedot:
            self.settings = []
        case .iob:
            self.settings = [
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
                MenuBarItemSetting(key: .icon, value: .iconColorHidden),
                MenuBarItemSetting(key: .iconPlacement, value: .iconPlacementLeading),
            ]
        case .cob:
            self.settings = [
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
                MenuBarItemSetting(key: .icon, value: .iconColorHidden),
                MenuBarItemSetting(key: .iconPlacement, value: .iconPlacementLeading),
            ]
        case .eventualglucose:
            self.settings = [
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
                MenuBarItemSetting(key: .icon, value: .iconColorHidden),
                MenuBarItemSetting(key: .iconPlacement, value: .iconPlacementLeading),
            ]
        case .loopstatus:
            self.settings = [
                MenuBarItemSetting(key: .displayTextAndIcon, value: .displayBoth),
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
                MenuBarItemSetting(key: .icon, value: .iconColorHidden),
                MenuBarItemSetting(key: .iconPlacement, value: .iconPlacementLeading),
            ]
        case .separator:
            self.settings = [
                MenuBarItemSetting(key: .textColor, value: .textColorDefault),
                MenuBarItemSetting(key: .fontWeight, value: .fontWeightRegular),
                MenuBarItemSetting(key: .character, value: .separatorCharPipe),
            ]
        }
    }

    public static func == (lhs: MenuBarItemContainer, rhs: MenuBarItemContainer) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(settings, forKey: .settings)
        try container.encode(type, forKey: .type)
    }

    func get(_ key: settingKey) -> settingValue {
        let setting = settings.filter { $0.key == key }.first?.value
        if setting == nil {
            return .none
        }

        return setting ?? .none
    }

    @MainActor
    func set(_ key: settingKey, _ val: settingValue) {
        self.objectWillChange.send()
        let indices = settings.indices.filter { settings[$0].key == key }
        if indices.count == 0 {
            self.settings.append(MenuBarItemSetting(key: key, value: val))
            return
        }

        let index = indices.first!
        self.settings[index] = MenuBarItemSetting(key: key, value: val)

        _ = self.settings.publisher.sink(receiveCompletion: { _ in
            NotificationCenter.default.post(name: Notification.Name("menuitemsettingchange"), object: nil)
        }, receiveValue: { _ in
            self.objectWillChange.send()
        })
    }
}
