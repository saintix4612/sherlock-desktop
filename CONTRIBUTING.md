# Contributing

Issues and pull requests are welcome. Describe the problem, your macOS version, CPU architecture, and Sherlock version. Remove private usernames, profile information, local account paths, and credentials from logs before posting them publicly.

## Develop

1. Install Apple's Command Line Tools and Python 3.
2. Edit `SherlockDesktop.swift` or the scripts/resources.
3. Run `bash Scripts/build.sh`.
4. Run `bash Tests/test.sh`. These tests use synthetic output and do not contact websites.
5. Open `build/Sherlock Desktop.app` to check the interface.

Keep changes focused. Add meaningful tests when changing search processing, validation, subprocess lifecycle, or exports. Explain the change and how you verified it in your pull request.

Search engine changes belong in the upstream [Sherlock Project](https://github.com/sherlock-project/sherlock). This repository maintains the Mac interface. Contributions are provided under this repository's MIT license.
