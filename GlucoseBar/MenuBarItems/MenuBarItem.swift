//
//  MenuBarItem.swift
//  GlucoseBar
//
//  Created by Andreas Stokholm on 2025-06-16.
//

import SwiftUI

public enum MenuBarItem: String, CaseIterable, Identifiable, Sendable, Codable {
    case glucosevalue
    case glucosetrend
    case glucosedelta
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

public struct MenuBarItemSetting: Codable {
    var key: String
    var value: String
}

public class MenuBarItemContainer: Equatable, Identifiable, Hashable, Codable {
    public var type: MenuBarItem
    public var settings: [MenuBarItemSetting]?

    private enum CodingKeys : String, CodingKey {
        case type = "type"
        case settings = "settings"
    }

    required public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(MenuBarItem.self, forKey: .type)
        do {
            self.settings = try container.decode([MenuBarItemSetting].self, forKey: .settings)
        } catch {
            // Noop, but important for scenarios where a container carries no settings
        }
    }

    init(type: MenuBarItem) {
        self.type = type
    }

    public static func == (lhs: MenuBarItemContainer, rhs: MenuBarItemContainer) -> Bool {
        return ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    @MainActor
    func getView() -> any View {
        switch type {
        case .glucosevalue:
            return GlucoseValueView()
        case .glucosetrend:
            return GlucoseTrendView()
        case .glucosedelta:
            return GlucoseDeltaView()

        case .loopstatus:
            return LoopStatusView()
        case .eventualglucose:
            return EventualGlucoseView()
        case .cob:
            return COBView()
        case .iob:
            return IOBView()

        case MenuBarItem.separator:
            return SeparatorView()
        }
    }

}
