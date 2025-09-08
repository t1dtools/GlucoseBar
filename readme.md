# GlucoseBar

GlucoseBar is a macOS 14+ Menu Bar application for monitoring your or your loved ones CGM readings at a glance.

You can download GlucoseBar from the [releases section](https://github.com/t1dtools/GlucoseBar/releases) here on GitHub, or from the [macOS App Store](https://apps.apple.com/app/glucosebar/id6468110131).

## CGM Providers

Name | Supported | Notes
----|----|----
Nightscout | ✅ | Uses APIv3, and thus does not make use of your API secret, but instead a token.
Dexcom Share | ✅ | Use your Dexcom account credentials, and ensure you have at least one follower.
Libre LinkUp | 🛑 | Abbott is deprecating the API used for this and have not published a replacement yet. Once a new API is available this can be explored again.

If you have requests for any other CGM data providers, please get in touch through a ticket.

## Call for Translations

GlucoseBar is available in the following languages currently:

- English
- French
- Danish

If you would like to help translate GlucoseBar into your language, please send an email to glucosebar@t1d.tools with the language you would like to help with, and we can take it from there.

## Readings from  Nightscout

To configure nightscout, input your Nightscout instance URL with no path. Eg. `https://my.ns.service.com`. If you use a non-standard port, add that after the domain `http://my.ns.service.com:1337`.

For the Token field, you need to create a token (referred to as `subjects` in the Nightscout admin console) in nightscout with the `readable` permission.

### Trio integration

The 1.3.0 release of GlucoseBar adds support for the algorithmic output from the [Trio project](https://github.com/nightscout/trio). If you are using Trio as the AID system for your insulin delivery, you can now see some of the Trio algorithmic output in GlucoseBar, presented in a familiar way by enabling the integration in the Nightscout CGM settings screen.

## Readings from Dexcom Share

To get up and running with Dexcom Share, please ensure you already have a follower set up using the normal Dexcom Share flow. Once that prerequisite is met, please continue using your normal Dexcom credentials. Remember to select the correct region.

## Disclaimer

GlucoseBar is for monitoring purposes only. Do not use the data from GlucoseBar for medical decisions.

See the full disclaimer in the [medical disclaimer](medical-disclaimer.txt).
