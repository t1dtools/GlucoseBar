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
            return "Glucose Value"
        case .glucosetrend:
            return "Glucose Trend"
        case .glucosedelta:
            return "Glucose Delta"
        case .glucosedot:
            return "Glucose Dot"

        // Trio
        case .loopstatus:
            return "Loop Status"
        case .eventualglucose:
            return "Eventual Glucose"
        case .iob:
            return "Insulin On Board"
        case .cob:
            return "Carbs On Board"

        // Separator
        case .separator:
            return "Separator"

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

        // TODO: Assign settings depending on type
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

//        self.settings.publisher.sink(receiveCompletion: {
//            print ("completion: \($0)")
//            print("here is when we should somehow update the view")
//        }, receiveValue: {
//            print ("value: \($0)")
//            self.objectWillChange.send()
//        })
    }

    @MainActor
    func getView() -> any View {
        switch type {
        case .glucosevalue:
            return GlucoseValueView(viewSettings: self)
        case .glucosetrend:
            return GlucoseTrendView(viewSettings: self)
        case .glucosedelta:
            return GlucoseDeltaView(viewSettings: self)
        case .glucosedot:
            return ZenModeView()

        case .loopstatus:
            return LoopStatusView(viewSettings: self)
        case .eventualglucose:
            return EventualGlucoseView(viewSettings: self)
        case .cob:
            return COBView(viewSettings: self)
        case .iob:
            return IOBView(viewSettings: self)

        case MenuBarItem.separator:
            return SeparatorView(viewSettings: self)
        }
    }

}
