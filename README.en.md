# DL Rooz for Apple TV

[فارسی](README.md)

A native tvOS app for watching the films and series available to your DL Rooz account, designed for Apple TV and its remote.

> **Note:** This is an unofficial app and is not affiliated with or endorsed by the DL Rooz website. The app does not host or store any content; it only shows what your own account on the site can already access.

## Requirements

- **An active DL Rooz account (username and password).** The app has no sign-up; if you don't have an account, create one on the website first.
- An Apple TV running **tvOS 17** or later.
- A Mac with **Xcode 16** or later to build the app.

## How it works

- **Sign in:** once, with your username (or email) and password. If the site asks to confirm a new device, the app asks for your mobile number (or email). Credentials stay only in this Apple TV's Keychain, and the Apple TV counts as one of your account's devices.
- **Home:** featured banner, Continue Watching and the site's rows.
- **Films and Series:** categories plus filters for genre, year, minimum IMDb score and sort order.
- **My List:** your account's watchlist from the site.
- **Search:** Apple TV keyboard and dictation, with an All / Movies / Series switch.
- **Title page:** Play or Resume, original or Persian-dub version, seasons and episodes, mark as watched.
- **Playback:** in the built-in player or in another app such as Infuse or VLC (chosen in Settings).
- **Built-in player:** buffers 5, 10 or 20 minutes ahead, quality picker, playback speed, resume and next-episode autoplay.
- **Subtitles:** the site's own subtitles, plus online search on SubDL, SubSource and OpenSubtitles with your own API keys (Settings → Online subtitle sources). Size, colour, background and timing can be adjusted.
- **Language:** Persian right-to-left interface, switchable to English in Settings.

## Installation

No ready-made IPA is published; you build and sign the app yourself from this repository. There are two ways:

### Option 1 (recommended): build an IPA and sign it with Signulous

[Signulous](https://www.signulous.com) is a paid (yearly subscription) app signing service that supports Apple TV. Apps signed with it stay valid for a year, so you don't need to reinstall every week.

1. Download the repository on your Mac:

   ```
   git clone https://github.com/Daariush/DLRooz-tvOS.git
   cd DLRooz-tvOS
   ```

2. Build an unsigned IPA:

   ```
   xcodebuild -project DLRooz.xcodeproj -scheme DLRooz -configuration Release \
     -sdk appletvos -derivedDataPath build CODE_SIGNING_ALLOWED=NO
   mkdir -p Payload && cp -R build/Build/Products/Release-appletvos/DLRooz.app Payload/
   zip -r DLRooz.ipa Payload
   ```

3. Create a Signulous account and register your Apple TV (follow Signulous's own Apple TV instructions).

4. Upload `DLRooz.ipa` in Signulous's app signing section, sign it, and install it on your Apple TV.

### Option 2 (free): install directly from Xcode

1. Open `DLRooz.xcodeproj` in Xcode. Xcode fetches the project's one dependency, [SwiftSoup](https://github.com/scinfu/SwiftSoup).
2. Select the **DLRooz** target → *Signing & Capabilities*, pick your team (a free Apple ID works) and change the **Bundle Identifier** to something unique, such as `com.yourname.dlrooz`.
3. Pair your Apple TV with Xcode: on the Apple TV go to *Settings → Remotes and Devices → Remote App and Devices*, and in Xcode open *Window → Devices and Simulators*.
4. Choose your Apple TV as the destination and press **Run**.

With a free Apple ID the app stops working after 7 days and must be reinstalled from Xcode. With a paid Apple Developer account it lasts a year.

## Notes

- The site's stream link is valid for about a minute, so external players are opened right away with a fresh link.
- The site's own subtitles are only available in the built-in player.
- tvOS gives apps no durable file storage: sign-in details and keys are kept in the Keychain, settings and watch progress in UserDefaults.

## License

The code in this repository is released under the [MIT License](LICENSE). The [Vazirmatn](https://github.com/rastikerdar/vazirmatn) font is used under the SIL Open Font License (`Config/OFL-vazirmatn.txt`).

Names and trademarks of the websites and services mentioned belong to their owners.
