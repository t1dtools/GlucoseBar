//
//  SettingsIdentifier.swift
//  GlucoseBar
//

import Foundation

/// Helpers for reading settings that older versions of the app persisted as a
/// *localized display name* instead of a stable identifier.
///
/// Storing the display name meant the loader compared the stored string against
/// the name in the *current* language and, finding no match, fell back to the
/// default. Changing the app language therefore silently reset the CGM provider,
/// the glucose unit, the colour scheme and the forecast style (and the next save
/// wrote the default back, destroying the original choice for good). Non-English
/// users were affected as soon as they switched to English, or vice versa.
///
/// New saves use `rawValue`. This resolves legacy values by checking the stored
/// string against the localized name in *every* language the app ships, so an
/// installation that is already broken is repaired on the next launch.
enum SettingsIdentifier {

    /// Resolves a persisted value onto a case of a string-backed enum.
    ///
    /// Matches, in order: the stable raw value, the current localized name, then
    /// the localized name in any other shipped language.
    ///
    /// - Parameter sourceName: the **English source string** passed to
    ///   `String(localized:)` for the case, not the translated result.
    static func resolve<T: CaseIterable & RawRepresentable>(
        _ stored: String,
        in type: T.Type,
        sourceName: (T) -> String,
        bundle: Bundle = .main
    ) -> T? where T.RawValue == String {
        guard !stored.isEmpty else { return nil }

        if let exact = T.allCases.first(where: { $0.rawValue == stored }) {
            return exact
        }

        return T.allCases.first {
            localizedForms(of: sourceName($0), in: bundle).contains(stored)
        }
    }

    /// The source string itself plus its translation in every localization
    /// shipped in `bundle`. Falls back to just the input when the bundle carries
    /// no localizations.
    static func localizedForms(of source: String, in bundle: Bundle = .main) -> Set<String> {
        var forms: Set<String> = [source]

        for localization in bundle.localizations where localization != "Base" {
            guard let path = bundle.path(forResource: localization, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path) else { continue }
            forms.insert(localizedBundle.localizedString(forKey: source, value: source, table: nil))
        }

        return forms
    }
}
