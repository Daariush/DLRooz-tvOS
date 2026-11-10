# DL Rooz for Apple TV

A native tvOS app for DLRooz, ported from the Android TV app [DRooz-AndroidTV](https://github.com/AliKarami/DRooz-AndroidTV).
It is an unofficial client: you need your own DLRooz account.

## Features

- **Sign in once.** Username (or email) and password; when the site asks a new device to confirm the account,
  the app asks for the mobile number (or email) as a second step. Credentials and the site session live in the
  Apple TV Keychain, and expired sessions are renewed silently without registering a new device.
- **Apple TV design.** Top tab bar (Home, Series, Films, My List, Search, Settings), focusable cards with the
  standard tvOS lift effect, the native search keyboard (with dictation), and Persian right-to-left UI
  (switchable to English in Settings).
- **Home:** featured carousel, Continue Watching (local progress plus the site's recently streamed list), and the
  site's rows. Series/Films pages have the site's categories as chips and infinite scrolling.
- **Title page:** adaptive Play / Resume button, original vs Persian-dub switch, My List, seasons and episode tiles
  with ✓ watched and progress, and suggestions.
- **Choose the player.** The built-in player (Apple's AVPlayerViewController) or hand the stream to Infuse, VLC,
  SenPlayer or any app via a custom URL scheme. Pick a default in Settings or "Ask every time"; "Play with…" is
  always on the title page.
- **Built-in player:**
  - Buffer ahead **5, 10 or 20 minutes** (Settings, or live from the player's Buffer menu, which also shows how
    much is loaded). Starts on the first variant for a fast start, then adapts.
  - Quality menu with the site's labels (e.g. `1080 [ 2.48 GB ]`), speed 0.5×–2×, resume, next-episode autoplay,
    audio tracks (original, 5.1, Persian dub) from the native audio menu.
  - **Subtitles:** the site's Farsi / English / English + Farsi / Farsi-for-dub tracks, plus online search on
    **SubDL**, **SubSource** and **OpenSubtitles** (by IMDb id, season and episode). Size, colour, background box,
    and sync in ±0.5 s / ±2 s steps (remembered per episode). Persian Windows-1256 files are decoded correctly.

## Online subtitle sources

Add your own keys in **Settings → Online subtitle sources** (stored in the Keychain):

| Site | What you need |
|---|---|
| SubDL | API key from subdl.com/panel/api |
| SubSource | API key from subsource.net (API docs page) |
| OpenSubtitles | API key from opensubtitles.com/consumers, plus your opensubtitles.com username and password for downloads |

The **Test with a film** button checks each key.

## Build

Requirements: Xcode 16 or newer, tvOS 17+ Apple TV (or the tvOS Simulator).

1. Open `DLRooz.xcodeproj`. Xcode fetches the one dependency, [SwiftSoup](https://github.com/scinfu/SwiftSoup).
2. Select the **DLRooz** target → *Signing & Capabilities* and pick your team (a free Apple ID works for
   installing on your own Apple TV).
3. Pair your Apple TV with Xcode (*Window → Devices and Simulators*; on the TV: Settings → Remotes and Devices →
   Remote App and Devices) and press Run.

## Notes

- tvOS has no durable file storage for apps: the session and secrets are in the Keychain, watch progress and
  settings in UserDefaults, images in the cache directory.
- The site's stream link expires about a minute after it is issued, so external players are opened immediately
  with a fresh link. Site subtitles need the site session, so they are only available in the built-in player.
- Audio Boost from the Android app is not available: AVPlayer doesn't allow audio processing on HLS streams.
- The buffer setting maps to `AVPlayerItem.preferredForwardBufferDuration`; tvOS treats it as a target and may
  buffer less when memory is tight.

Fonts: [Vazirmatn](https://github.com/rastikerdar/vazirmatn) (SIL Open Font License, see `Config/OFL-vazirmatn.txt`).
