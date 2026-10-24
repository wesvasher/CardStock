# CardStock

A native macOS editor for flat-file blogs and portfolio sites.

CardStock edits your site's files locally, uses **GitHub** for source and version history, and works with **Cloudflare Pages** (or any Git-connected host) to publish automatically when you push.

> Status: early development.

## Download

Get the latest `.dmg` from [Releases](../../releases/latest). Requires macOS 26 or later.

Builds are not yet notarized by Apple. On first launch, right-click CardStock.app → **Open**, or allow it under System Settings → Privacy & Security.

## Building from source

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
scripts/build.sh        # Debug build, then launch
scripts/make-dmg.sh     # Release build → dist/CardStock-<version>.dmg
```

The Xcode project is generated from `project.yml`. Run `xcodegen generate` and open `CardStock.xcodeproj` if you want to work in Xcode.

## Releasing

Push a version tag and GitHub Actions builds the DMG and attaches it to a GitHub Release, with the tagged commit's message as the notes:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## License

[PolyForm Noncommercial 1.0.0](LICENSE), with an added permission: anyone may use CardStock to make and publish websites for any purpose, including commercial sites. You may download, use, change and share CardStock for noncommercial purposes, but not sell it, charge for it, or use its code in anything sold or offered commercially. Versions before 0.4.0 were released under the MIT License.
