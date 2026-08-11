# Kioku

**Translate any text you select on macOS. Your history becomes study material — and each week, AI picks the expressions worth keeping.**

[日本語版 README](README.ja.md)

<!-- スクリーンショット: ポップアップ翻訳（選択 → アイコン → 訳文） -->

Kioku is a menu bar app for Japanese speakers learning English. Select text in any
app and it translates in place. What you looked up accumulates as study material,
and once a week an AI reviews your history and proposes only the expressions that
are worth remembering — which you then review with spaced repetition.

It is not a general-purpose translator. It is built around a single loop:
**translate what you actually run into, then remember the parts that matter.**

## Features

- **Translate anywhere** — select text in any app; a small icon appears, and one
  click shows the translation. Works in browsers, Slack, PDFs, editors.
- **Replace in place** — writing English? Select your Japanese, and Kioku swaps it
  for the English you pick. No copying into a browser and back.
- **Ask for a different tone** — regenerate with a direction: more casual, more
  formal, or shorter.
- **Explain it** — expand "詳しく" for the grammar and nuance behind a translation.
- **Weekly report** — an AI reads your week of translations, points out patterns you
  keep stumbling on, and proposes flashcards. You approve the ones you want.
- **Spaced repetition** — review approved cards with a three-way self rating,
  capped at 20 cards a day so a session stays under five minutes.
- **Two engines** — Gemini (cloud, more natural, supports tone control) or Apple
  Translation (on-device, offline, free, nothing leaves your Mac).

<!-- スクリーンショット: 週次レポート／復習画面 -->

## Privacy

Kioku is built so that you can tell exactly when text leaves your machine.

- **Nothing is sent until you click.** Selecting text only shows an icon. No
  network request happens until you act on it.
- **Choose an engine that never sends anything.** With Apple Translation, all
  translation happens on-device. Offline, free, and nothing leaves your Mac.
- **With Gemini, it is your key and your account.** Kioku has no server. Text goes
  from your Mac to the provider you configured, and nowhere else.
- **Excluded apps.** Password managers are excluded out of the box, and you can add
  any app. In excluded apps the icon never appears at all.
- **Your data stays local.** History, cards, and reports live in a local SQLite
  database in your Application Support folder.

Note that if you use a free-tier API key, your provider's terms may allow them to
use submitted content to improve their products. Check your provider's terms, or
use Apple Translation if that matters to you.

## Requirements

- macOS 26.0 or later (Apple Translation requires macOS 26.4)
- Accessibility permission — required to read the text you select
- A Gemini API key, if you want to use the Gemini engine
  ([get one here](https://aistudio.google.com/apikey))

Kioku cannot be distributed on the Mac App Store: reading selected text system-wide
requires the Accessibility API, which is incompatible with App Store sandboxing.

## Installing

Pre-built binaries are not published yet. Build from source for now.

## Building from source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
git clone https://github.com/dai199/kioku.git
cd kioku
make run     # generate the project, build, and launch
```

### Signing

By default the build is ad-hoc signed, so it works without any Apple Developer
account. Nothing to configure.

If you have an Apple ID registered in Xcode (a free one is enough), pass your team
ID instead:

```sh
make build TEAM=XXXXXXXXXX   # Xcode > Settings > Accounts
```

This is worth doing if you plan to keep using Kioku. macOS ties the Accessibility
permission to the app's code signature, and an ad-hoc signature changes every time
you rebuild — meaning you have to grant the permission again after each update. A
signature from your own certificate stays stable.

`Kioku.xcodeproj` is generated from `project.yml` and is not tracked in git. Always
edit `project.yml` for target, build setting, and dependency changes.

```sh
make build   # xcodegen generate → xcodebuild build
make test    # unit tests
make run     # build and launch (kills a running instance first)
make clean   # remove .build and the generated project
```

## Documentation

- [SPEC.md](SPEC.md) — requirements, data model, roadmap. The source of truth for
  what gets built.
- [DESIGN.md](DESIGN.md) — the design language every screen follows.
- [CLAUDE.md](CLAUDE.md) — conventions and invariants for working in this codebase.

**These documents and the code comments are written in Japanese.** The comments
carry the reasoning behind design decisions, not just descriptions, so they are
worth reading if you plan to contribute.

## Contributing

Issues and pull requests are welcome. Please open an issue first for anything
substantial, so we can agree on the approach before you spend time on it.

By contributing you agree that your contribution is licensed under AGPL-3.0.

## License

[AGPL-3.0](LICENSE) © 2026 Tagami Daiki

The AGPL was chosen so that modified versions stay open, including versions run as
a hosted service. Commercial use is permitted; what the license requires is that
the source stays available.
