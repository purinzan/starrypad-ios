# App Review — reply for Guideline 2.1 (Information Needed)

Paste the block below into **App Store Connect → App Review Information → Notes**,
and also send it as the Resolution Center reply. Attach the screen recording
described at the end.

---

## Notes field (copy from here)

```
Starrypad is a standalone musical instrument. There is no account, no login, no
purchase or subscription, no user-generated content shared between users, and no
network communication of any kind. Everything below is available immediately on
first launch.

1. SCREEN RECORDING
A recording captured on a physical iPhone 17e running iOS 26.6 is attached. It
starts from the Home Screen and covers: playing the pads, switching kits,
recording and overdubbing a loop, undoing one pass, the mixer, sampling from the
microphone (including the microphone permission prompt), sampling audio from a
video (including the system video picker), trimming a sample onto a pad, and
exporting the loop to the system share sheet.

2. DEVICES AND OPERATING SYSTEMS TESTED
- iPhone 17e, iOS 26.6 (physical device; primary test device)
- iPhone 17e simulator, iOS 26.5
- iPhone 17 Pro simulator, iOS 26.5
- iPhone 17 Pro Max simulator, iOS 26.5
Deployment target is iOS 17.0. The app is iPhone only.

3. FUNCTION AND AUDIENCE
Starrypad is a drum pad, looper and sampler for iPhone.

Problem it solves: people who make music have rhythm ideas away from their
studio - commuting, on a break, before sleep - and those ideas are lost by the
time they reach their equipment. Starrypad is for capturing one before it is
forgotten, and getting it out to a computer afterwards.

Audience: anyone who makes beats or plays drums, from beginners to people who
already use a DAW. It is not a game and contains no objectionable content; it is
suitable for all ages.

Value: velocity comes from how hard the screen is struck, read from the
accelerometer, rather than from where on the pad the finger landed, so the app
plays like an instrument rather than a set of buttons. Recording waits for the
bar line so that overdubbing never interrupts what is already playing. Finished
loops can be exported as WAV or MIDI.

4. SETTING UP AND REACHING THE MAIN FEATURES
No setup, no credentials, and no sample files are required. Launch the app and
the instrument is on screen.

- Play: tap the sixteen pads. Harder taps are louder.
- Change kit: the four buttons above the pads (A Acoustic, B 808, C, D).
- Record a loop: tap Rec. The app counts one bar, then records. Tap pads to play
  into it. Tap Rec again to stop recording and keep the loop playing. Tap Undo to
  remove the most recent layer.
- Mixer: the Mixer button at the top. Level, pan, tuning, mute and solo for the
  selected pad.
- Sampler: the Sampler button at the top. "Record from the microphone" records a
  new sound (this is the only place the microphone is requested). "Take the sound
  from a video" opens the system video picker. Drag on the waveform to choose the
  part that plays, then assign it to the selected pad.
- Export: the share icon at the top right, enabled once something is recorded.
  Choose WAV or MIDI; the file is handed to the standard iOS share sheet.
- Settings and credits: the gear and info icons at the top right.
- Rearrange pads: press and hold a pad, then drag it onto another.

5. EXTERNAL SERVICES, TOOLS OR PLATFORMS
None. The app uses no external services of any kind:
- no data providers, no authentication services, no payment processors, no AI
  services, no advertising, no analytics, no crash reporting
- no third-party SDKs or frameworks; only Apple frameworks (SwiftUI,
  AVFoundation, CoreMIDI, CoreMotion, PhotosUI, MessageUI)
- no network code whatsoever. The app behaves identically in Airplane Mode.

Audio samples are bundled inside the app. Nothing is downloaded at runtime.

6. REGIONAL DIFFERENCES
None. The app functions identically in every region. There is no
region-dependent content, no geolocation, and no server to vary behaviour. The
interface is available in English and Japanese, which changes wording only.

7. THIRD-PARTY MATERIAL AND AUTHORISATION
Starrypad is not in a regulated industry. It contains third-party audio samples,
all of which are used under licences that permit redistribution:

- Acoustic kit: Salamander Drumkit by Alexander Holm, licensed CC BY 3.0
  (https://creativecommons.org/licenses/by/3.0/). This licence requires
  attribution. Attribution is given inside the app, on the screen behind the
  info button at the top right, and again in the App Store description.
- 808 kit: Roland TR-808 Sound Sample Set by Michael Fischer, as published by
  the TidalCycles project under CC0 1.0
  (https://creativecommons.org/publicdomain/zero/1.0/). CC0 imposes no
  conditions.
- Glass sounds: generated for this app by the developer, not recorded.

The full terms are also published at
https://github.com/purinzan/starrypad-ios/blob/main/LICENSE-SAMPLES

ADDITIONAL NOTES

Permissions. The microphone is requested only when the reviewer taps "Record
from the microphone" inside the Sampler, and only to record the sound being
sampled onto a pad. Recordings stay on the device. The video picker is
PHPickerViewController, which runs outside the app, so the app never receives
access to the photo library - only to the single video chosen, and only long
enough to read the first thirty seconds of its audio. There is no App Tracking
Transparency prompt because the app does not track.

Background audio. The app declares the audio background mode so that sound
continues when the screen locks: a connected USB MIDI controller can still be
played, and a recorded loop keeps running. To see this, record a short loop,
press Play, and lock the phone; the loop continues.

USB MIDI. A class-compliant USB MIDI controller is supported but is not required
for review. Every feature is reachable from the pads on screen.
```

---

## Screen recording — what to capture

Record on the **physical iPhone 17e**, using Control Centre → Screen Recording.
Aim for 90–120 seconds. Do it in one take, unhurried, pausing a beat on each
screen so the reviewer can read it.

> **Do this first.** The microphone prompt only appears once per install. Delete
> Starrypad from the phone and install it again before recording, or the prompt
> Apple asked to see will not appear.

| # | Show | Why Apple asked |
| --- | --- | --- |
| 1 | The Home Screen, then tap the Starrypad icon to launch | "must begin with launching the app" |
| 2 | Tap several pads, hard and soft, so the loudness changes | core feature |
| 3 | Tap **B 808**, play a few pads, tap **A Acoustic** again | core feature |
| 4 | Tap **Rec**, wait through the four-count, play a bar, tap **Rec** again | core feature |
| 5 | Play more over the loop, then tap **Undo** once | core feature |
| 6 | Tap **Mixer**, turn LEVEL and PAN, tap a pad so it still sounds | core feature |
| 7 | Tap **Sampler** → **Record from the microphone** → **let the permission alert appear and tap Allow** | "any prompts requesting access to sensitive data" |
| 8 | Say or tap something for two seconds, stop, drag the waveform edges, assign it to a pad, then tap that pad | core feature |
| 9 | Tap **Sampler** → **Take the sound from a video** → let the picker appear, pick a video, wait for it to import | second permission-shaped flow |
| 10 | Tap the **share icon** → **音声で書き出す (WAV)** → let the share sheet appear, then close it | core feature |
| 11 | Tap the **gear** icon, scroll the settings, close it | completeness |
| 12 | Tap the **info** icon so the credits and contact screen is visible | shows the CC BY attribution in place |

Nothing in this app has account registration, login, account deletion, paid
content, subscriptions, or user-generated content shared with other users, so
those parts of Apple's list do not apply — the Notes text says so explicitly.

## Also worth doing before replying

- **Screenshots.** Apple's message repeats their 2.3.3 advice. Make sure the
  listing carries the four current screenshots rather than the single old one.
- **No new build is needed.** A 2.1 Information Needed rejection is answered by
  replying in Resolution Center; the same build resumes review.
