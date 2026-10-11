# Keytalk

Hold a key, speak, and let go: Keytalk types what you said into whatever app
you're using. It's a small, native macOS menu bar app that turns your speech
into text with Apple's built-in speech recognition. You don't need an
account, an API key, or a subscription.

This README is for Mac users who are comfortable building an app from source.
It covers what Keytalk does, how to build it, and how to use it.

> **Status:** early preview (0.1). Keytalk works day to day, but there's no
> prebuilt download yet. You build it from source in about a minute.

## Why Keytalk

- **Private by default.** Keytalk asks macOS to recognize speech on your Mac.
  On Macs that support on-device recognition for your language, your audio
  never leaves the computer. Otherwise, macOS uses Apple's speech service.
- **Native and small.** Keytalk is about 650 lines of Swift, with no
  Electron, no web views, and no dependencies. It starts instantly and stays
  out of the way.
- **Works in any app.** Keytalk pastes into native apps, browsers, Electron
  apps, and terminals alike.
- **Doesn't lose your words.** If there's no text field to paste into,
  Keytalk tells you and leaves the text on the clipboard.
- **Leaves your clipboard alone.** Keytalk restores whatever you'd copied
  after it pastes, and it marks its own text so clipboard managers skip it.

## Before you begin

You need the following:

- A Mac with Apple silicon, running macOS 12 or later.
- The Xcode Command Line Tools. To install them, run the following command:

  ```sh
  xcode-select --install
  ```

## Build Keytalk

1. Clone the repository and go into it:

   ```sh
   git clone https://github.com/monirz/keytalk.git
   cd keytalk
   ```

1. Optional: Create a local signing certificate:

   ```sh
   ./scripts/make-signing-cert.sh
   ```

   macOS ties Keytalk's Accessibility permission to the app's signature.
   Without this certificate, every rebuild counts as a new app, and you have
   to grant the permission again. The certificate lives in your login
   keychain and is only used to sign apps on your Mac.

1. Build the app:

   ```sh
   ./build.sh
   ```

   The app is written to `build/Keytalk.app`. If you skipped the previous
   step, the build prints a warning and signs the app without a certificate.

1. Optional: Move `build/Keytalk.app` to your `Applications` folder.

## Set up permissions

The first time you open Keytalk, macOS asks for three permissions. Keytalk
needs all three:

Accessibility
: Lets Keytalk notice the dictation key in any app and paste the text.

Microphone
: Lets Keytalk hear you while you hold the key.

Speech Recognition
: Lets macOS turn your recording into text.

To set up the permissions, do the following:

1. Open `Keytalk.app`.
1. When macOS asks for speech recognition and microphone access, click
   **Allow** both times.
1. When macOS asks about Accessibility, click **Open System Settings**, and
   then turn on **Keytalk** in **Privacy & Security** > **Accessibility**.

   Until you do, a banner at the bottom of the screen reads **Keytalk needs
   Accessibility**. The banner disappears about a second after you grant the
   permission.

## Dictate

1. Click in any text field.
1. Hold **Right Option (⌥)** and speak.

   A pill at the bottom of the screen shows **Listening…**.
1. Release the key.

   The pill shows **Transcribing…**, and then your text appears where you
   were typing, followed by a space.

Keytalk discards presses shorter than a quarter of a second, so tapping
Right Option by accident doesn't type anything.

To cancel a dictation, press **Esc** while you hold the key. Pressing any
other key while you hold the dictation key also cancels it. That way, Option
shortcuts such as **Option+Left Arrow** keep working.

### Change the dictation key

Keytalk adds a microphone icon to the menu bar. To change the key, click the
icon, and then select one of the following:

- **Right ⌥ Option** (default)
- **Right ⌘ Command**
- **Right ⌃ Control**
- **fn / 🌐**

On a MacBook with a notch, the menu bar icon can end up hidden behind the
notch when the menu bar is full. Keytalk keeps working. To see the icon,
quit another menu bar app, or use a menu bar manager to reorder the icons.

### Messages from Keytalk

The pill at the bottom of the screen also reports problems:

**No text field. Press ⌘V to paste.**
: No app accepted the text, for example because nothing was focused. Your
  text is on the clipboard, so you can click where you want it and press
  **Command+V**.

**Secure input is on in APP_NAME. Not pasted.**
: A password field or another secure input in `APP_NAME` blocks pasting,
  so Keytalk doesn't paste anything.

**Keytalk needs Accessibility.**
: Keytalk doesn't have the Accessibility permission. See
  [Set up permissions](#set-up-permissions).

## Language

Keytalk recognizes speech in your Mac's language and region, as set in
**System Settings** > **General** > **Language & Region**. If Apple doesn't
offer speech recognition for that language, Keytalk uses US English.

## Troubleshooting

**Nothing happens when I hold the key, even though Keytalk is on in
Accessibility settings.**
: You probably rebuilt Keytalk without a signing certificate, so macOS treats
  the new build as a different app. In **Privacy & Security** >
  **Accessibility**, select **Keytalk**, click **Remove (−)**, and then open
  Keytalk again. To stop this from happening after future rebuilds, run
  `./scripts/make-signing-cert.sh`, and then run `./build.sh`.

**The text isn't pasted, and I don't see any message.**
: Make sure you're holding the key you selected in the menu bar menu. To see
  what Keytalk is doing, run the following command, and then try again:

  ```sh
  log stream --predicate 'eventMessage CONTAINS "keytalk:"'
  ```

## How it works

- **Dictation key:** an event tap watches the dictation key system-wide. It
  runs on its own thread, so typing never waits on Keytalk.
- **Speech to text:** Apple's Speech framework transcribes the microphone
  audio, on device whenever your Mac supports it.
- **Pasting:** Keytalk checks that the app you were using is still in front,
  switching back to it if needed. Then it offers the text on the clipboard
  and presses **Command+V** for you.
- **Paste check:** Keytalk hands over the text only when the app asks for
  it. That tells Keytalk whether the paste worked.

The source is in [`Sources/`](Sources/):

| File | What it does |
|------|--------------|
| `main.swift` | Runs the app, the menu bar menu, and the dictation steps. |
| `HotkeyTap.swift` | Watches the dictation key. |
| `Transcriber.swift` | Records the microphone and turns the audio into text. |
| `TextInserter.swift` | Pastes the text and restores the clipboard. |
| `Indicator.swift` | Shows the status pill at the bottom of the screen. |

## License

Keytalk is available under the [MIT License](LICENSE).
