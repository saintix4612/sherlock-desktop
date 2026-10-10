# Sherlock Desktop

A small, open-source Mac app for searching public usernames with **Sherlock**, without typing a command for every search.

**Powered by [Sherlock](https://github.com/sherlock-project/sherlock), created by [Siddharth Dushantha](https://github.com/sdushantha) and maintained by the Sherlock Project contributors. All username-search functionality comes from their work.** This repository provides an independent SwiftUI interface; it is not an official Sherlock Project product and is not affiliated with or endorsed by the project.

## Features

- Enter a username and click Search.
- See matches as the search runs.
- Stop a search and keep partial results.
- Filter results, copy URLs, and open profiles in your browser.
- Export matches as CSV, with the search status included.
- Review search output, errors, and unavailable/skipped sites.
- Native macOS light and dark appearance.

## Requirements

- macOS 14 or newer.
- Apple Command Line Tools or Xcode with a Swift compiler.
- Python 3 and a working Sherlock installation at `~/.local/bin/sherlock`.

The build script targets the architecture of your Mac (Apple silicon or Intel). Apple silicon on macOS 26 has been tested locally; Intel builds and older supported macOS versions have not yet been verified.

## Install and run

### 1. Install Sherlock

Follow the [official Sherlock installation guide](https://sherlockproject.xyz/installation). With [Homebrew](https://brew.sh) already installed, one option is:

```sh
brew install pipx
pipx ensurepath
pipx install sherlock-project
```

Open a new Terminal window and verify:

```sh
sherlock --version
```

The app currently looks for `~/.local/bin/sherlock`, pipx's usual executable location. Custom locations are not yet configurable. Installing through `brew install sherlock` alone may put the executable elsewhere.

### 2. Build the Mac app

Install Apple's development tools if needed:

```sh
xcode-select --install
```

Clone this repository and build:

```sh
git clone https://github.com/saintix4612/sherlock-desktop.git
cd sherlock-desktop
bash Scripts/build.sh
open 'build/Sherlock Desktop.app'
```

You can move the built app to your Applications folder and keep it in your Dock. Keep the separate Sherlock installation installed. From then on, open the app, enter a username, and click Search.

The app is locally ad-hoc signed, not Developer ID signed or notarized. This initial release is distributed as source; no prebuilt download is required. It is a Mac app, even though the underlying Sherlock engine also runs on other operating systems.

## How it works

The SwiftUI interface launches your installed Sherlock as a subprocess, passing arguments directly without a shell. It parses Sherlock's plain-text output and displays matching profile links. The UI does not add a separate search engine or improve Sherlock's detection accuracy.

Searches contact supported third-party websites using your network connection. Results remain in the app's memory unless you export them; the interface has no analytics or cloud backend. Opening a profile sends you to that website in your browser. Temporary search working directories are removed after completion.

A matching username does **not** prove that accounts belong to the same person. False matches, rate limits, bot protection, timeouts, and unsupported username formats can affect results. An empty result list does not prove a username is unused. Use the tool responsibly and respect people's privacy and website rules.

## Development and tests

```sh
bash Scripts/build.sh
bash Tests/test.sh
```

Offline tests cover validation, result parsing, duplicate handling, URL restrictions, CSV escaping, unavailable-site tracking, subprocess streaming, failed exits, restarting, and cancellation. They use synthetic output and make no network requests. GitHub Actions runs the build and tests on macOS.

Local verification used Sherlock 0.16.2 with Python 3.14.7. The app window and input validation were inspected manually. No live username search was used as an automated test. Future Sherlock output changes may require parser updates.

To update Sherlock separately:

```sh
pipx upgrade sherlock-project
```

See [CONTRIBUTING.md](CONTRIBUTING.md) to help improve the interface.

## Credit and licensing

- **Search engine:** [Sherlock Project](https://github.com/sherlock-project/sherlock), originally created by Siddharth Dushantha, with contributions from its community. Sherlock is MIT licensed and is installed separately, not bundled here.
- **Desktop interface:** maintained by [saintix4612](https://github.com/saintix4612) and contributors; initially developed with assistance from OpenAI Codex.
- **Interface license:** [MIT](LICENSE), allowing use, modification, and redistribution under its terms.
- **Upstream attribution:** see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for Sherlock's license and attribution.

Please credit the Sherlock Project when sharing this app. The original project does the searching; this project makes it easier to use on a Mac.
