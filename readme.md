# GlucoseBar

GlucoseBar is a macOS 14+ Menu Bar application for monitoring your or your loved ones CGM readings at a glance.

You can download GlucoseBar from the [releases section](https://github.com/t1dtools/GlucoseBar/releases) here on GitHub, or hopefully soon from the macOS App Store.

## CGM Providers

Name | Supported | Notes
----|----|----
Nightscout | ✅ | Uses APIv3, and thus does not make use of your API secret, but instead a token.
Dexcom Share | ✅ | Use your Dexcom account credentials, and ensure you have at least one follower.
Libre LinkUp | ⏳️ | Basic functionality is in, but I need testing help from an actual Libre user.

If you have requests for any other CGM data providers, please get in touch through a ticket.

## Readings from  Nightscout

To configure nightscout, input your Nightscout instance URL with no path. Eg. `https://my.ns.service.com`. If you use a non-standard port, add that after the domain `http://my.ns.service.com:1337`.

For the Token field, you need to create a token in nightscout with the `readable` permission.

## Readings from Dexcom Share

To get up and running with Dexcom Share, please ensure you already have a follower set up using the normal Dexcom Share flow. Once that prerequisite is met, please continue using your normal Dexcom credentials. Remember to select the correct region.

## Disclaimer

GlucoseBar is for monitoring purposes only. Do not use the data from GlucoseBar for medical decisions.

See the full disclaimer in the [medical disclaimer](medical-disclaimer.txt).
