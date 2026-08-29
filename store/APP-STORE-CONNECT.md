# App Store Connect — everything to paste

Version 1.0, build 1. Bundle ID `com.purinzan.starrypad`.

Screenshots are in `screenshots/6.9-inch/`, at 1320 × 2868, which is the only
size App Store Connect requires — it scales that set down for every other
iPhone.

Turn the two pages under `docs/` into URLs by enabling GitHub Pages on this
repository: Settings → Pages → Source: `main`, folder `/docs`. That gives you
`https://purinzan.github.io/starrypad-ios/` for support and
`https://purinzan.github.io/starrypad-ios/privacy.html` for the policy.


## App information

| Field | Value |
| --- | --- |
| Name | Starrypad |
| Subtitle | Drum pads, looper and sampler |
| Category | Music (secondary: Entertainment) |
| Age rating | 4+ — nothing to declare in the questionnaire |
| Support URL | https://purinzan.github.io/starrypad-ios/ |
| Privacy policy URL | https://purinzan.github.io/starrypad-ios/privacy.html |


## Description

Sixteen pads, an acoustic kit and an 808, and a loop you can play into.

Hit the pads with your fingers and Starrypad listens to how hard, not where:
the accelerometer reads the strike, so a ghost note is a ghost note and an
accent is an accent. Two fingers land at once. The hi-hat chokes the way a
hi-hat does.

Press Rec and it counts you in for a bar, then loops. Play over the top as
many times as you like — undo peels off one pass round the loop, newest
first, rather than throwing away the take. Move the tempo while it plays and
the beat holds still underneath you.

Sample anything. Record from the microphone or take the audio out of a video,
drag on the waveform to pick the part that sounds, and drop it on a pad. The
original is kept, so you can come back and re-trim it later.

Rearrange the kit by holding a pad and dragging it onto another. Everything
travels with the sound: level, pan, tuning, trim, name, and whatever you have
already recorded with it.

Plug in a class-compliant USB MIDI controller and play it from that instead.
If the pads come out in the wrong order, tap Learn and hit each one once.

No account. No analytics. No network. Everything stays on the phone.

Sounds: the acoustic kit is the Salamander Drumkit by Alexander Holm (CC BY
3.0). The 808 kit comes from Michael Fischer's TR-808 sample set as published
by TidalCycles (CC0 1.0).


## 日本語（App Store Connect の「日本語」ローカリゼーション）

配信地域に日本を含めるなら、日本語のローカリゼーションが要ります。英語の直訳ではなく、
日本語で書き下ろしています。

### 名前 / サブタイトル

Starrypad
パッド・ループ・サンプラー

### 説明

16個のパッド、アコースティックキットと808、そして叩き込めるループ。

指で叩くと、Starrypad は「どこを叩いたか」ではなく「どれだけ強く叩いたか」を聞いています。
加速度センサーが打撃そのものを読むので、ゴーストノートはゴーストノートに、アクセントは
アクセントになります。2本の指が同時に着地します。ハイハットは、ハイハットのように
チョークします。

RECを押すと1小節カウントしてからループが始まります。何度でも上から重ねてください。
UNDOはテイクごと捨てるのではなく、ループ1周ぶんを新しい順に剥がします。
再生中にテンポを動かしても、拍は足元で静止したままです。

何でもサンプリングできます。マイクで録るか、動画から音を取り出すか。波形をドラッグして
鳴らす範囲を決め、パッドに置く。元の録音は残るので、後から切り直せます。

キットの並べ替えは、パッドを長押ししてドラッグするだけ。レベル、パン、チューニング、
トリミング、名前、そしてすでに録音した演奏まで、すべてが音と一緒に移動します。

作ったループはWAVかMIDIで書き出せます。MIDIはドラム用のチャンネル10、ノート番号は
General MIDI準拠なので、そのままDAWで音色を差し替えられます。

クラスコンプライアントのUSB MIDIコントローラーを挿せば、そちらから演奏できます。
パッドの順番が違うときだけ、設定から並びを学習させてください。

アカウントなし。解析なし。ネットワーク通信なし。すべて端末の中だけで完結します。

音源：アコースティックキットは Alexander Holm 氏の Salamander Drumkit（CC BY 3.0）。
808は Michael Fischer 氏のTR-808サンプルセットを TidalCycles が公開したもの（CC0 1.0）。

### キーワード

ドラムパッド,ドラムマシン,サンプラー,ループ,ビートメイク,MIDI,グルーブボックス,808,パーカッション,DTM

### プロモーション用テキスト

ボタンを押した瞬間ではなく、小節線で録音が始まります。再生中にRECを押すと次の小節まで
待つので、いま鳴っている音は一切動きません。

### このバージョンでの変更点

初回リリース。


## Keywords

drum pad,drum machine,mpc,sampler,looper,beat maker,midi,groovebox,808,percussion


## Promotional text

Record on the bar line, not on the button press: hit Rec while a loop plays
and it waits for the bar before counting you in, so nothing you are hearing
moves.


## What's new in this version

First release.


## Review notes

Nothing is behind a login and no demo account is needed.

A USB MIDI controller is supported but not required — every feature can be
reached from the pads on screen. If you want to try MIDI, any class-compliant
controller connected through a powered adapter is named at the top of the
screen when it is seen.

The microphone is requested only when "Record from the microphone" is tapped
in the Sampler, and only to record a sound the user is sampling onto a pad.
Nothing is transmitted; the app has no network code at all.

The background audio mode is used so that sound keeps playing when the screen
locks or the app is backgrounded: a connected MIDI controller can still be
played, and a recorded loop keeps running. To see this, record a short loop,
press Play, and lock the phone — the loop continues.

The video picker uses PHPickerViewController out of process, so the app never
gains access to the photo library, only to the single video chosen.


## Encryption

Already declared in Info.plist (`ITSAppUsesNonExemptEncryption` = false), so
App Store Connect will not ask on upload.
