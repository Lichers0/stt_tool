# Distribution: Homebrew + Sparkle Auto-Updates

## Overview

Distribute STTTool as a closed-source macOS app with Homebrew for installation and Sparkle for auto-updates. Code stays private, compiled releases are public.

## Architecture

### Two Repositories

| Repo | Visibility | Contents |
|------|-----------|----------|
| `stt-tool` (current) | Private | Source code, GitHub Actions workflow |
| `stt-tool-releases` | Public | README, appcast.xml, Casks/, GitHub Releases (.zip) |

### Release Flow

```
git tag v1.3.1 && git push --tags
       |
GitHub Actions (private repo):
  1. xcodebuild archive -> STTTool.app
  2. ditto -c -k -> STTTool.zip
  3. sign_update (Sparkle EdDSA) -> signature + length
  4. gh release create in stt-tool-releases with .zip
  5. Update appcast.xml in stt-tool-releases
  6. Update Casks/stt-tool.rb (version + sha256)
       |
Users:
  - Homebrew: brew install --cask stt-tool
  - Sparkle: app checks appcast.xml -> downloads update
```

## Sparkle Integration

### Setup

- Add Sparkle via SPM (https://github.com/sparkle-project/Sparkle)
- Info.plist keys:
  - `SUFeedURL` = `https://raw.githubusercontent.com/<user>/stt-tool-releases/main/appcast.xml`
  - `SUPublicEDKey` = `<public EdDSA key>`

### EdDSA Keys

- Generate once: Sparkle's `generate_keys` tool
- Private key -> GitHub Secret `SPARKLE_PRIVATE_KEY`
- Public key -> embedded in Info.plist (`SUPublicEDKey`)

### Update Behavior

- On app launch, Sparkle checks appcast.xml (every 24h by default)
- If new version available: shows standard macOS update dialog
- User clicks "Update" -> downloads .zip -> replaces .app -> relaunch

### UI Changes (Settings > General)

- Add "Check for Updates" button (calls `SUUpdater.checkForUpdates()`)
- Optional: toggle "Auto-check for updates"

## Homebrew Cask

### Formula: `Casks/stt-tool.rb`

```ruby
cask "stt-tool" do
  version "1.3.1"
  sha256 "abc123..."

  url "https://github.com/<user>/stt-tool-releases/releases/download/v#{version}/STTTool.zip"
  name "STT Tool"
  desc "Speech-to-text tool for macOS"
  homepage "https://github.com/<user>/stt-tool-releases"

  app "STTTool.app"
end
```

### User Commands

```bash
# First install
brew tap <user>/tap https://github.com/<user>/stt-tool-releases
brew install --cask stt-tool

# Manual update (Sparkle handles this automatically)
brew upgrade stt-tool
```

Homebrew is for initial installation only. After that, Sparkle handles updates.

## GitHub Actions Workflow

### Trigger

Tag push matching `v*` pattern.

### Steps

1. Checkout private repo
2. Cache SPM dependencies
3. `xcodebuild archive` -> STTTool.app
4. `ditto -c -k` -> STTTool.zip
5. Sparkle `sign_update STTTool.zip` with EdDSA private key -> get signature + length
6. `gh release create` in `stt-tool-releases` with STTTool.zip attached
7. Generate/update `appcast.xml` with new `<item>` entry
8. Update `Casks/stt-tool.rb` with new version + sha256
9. Commit + push appcast.xml and Casks/ to stt-tool-releases

### GitHub Secrets (Private Repo)

| Secret | Purpose |
|--------|---------|
| `SPARKLE_PRIVATE_KEY` | EdDSA key for signing updates |
| `RELEASES_PAT` | Personal Access Token with push access to public repo |

### Release Notes

Taken from tag annotation body, or CHANGELOG.md if present.

## Public Repo Structure

```
stt-tool-releases/
  README.md          # Description, screenshots, install instructions
  appcast.xml        # Sparkle feed (auto-updated by CI)
  Casks/
    stt-tool.rb      # Homebrew cask formula (auto-updated by CI)
```

## Code Signing Note

No Apple Developer ID ($99/year). Consequences:
- First launch: user must right-click -> Open -> confirm, or run `xattr -cr /Applications/STTTool.app`
- Sparkle uses EdDSA signature (not Apple codesign) to verify update integrity
- Document the first-launch workaround in public repo README

## Files to Change

### Private repo (stt-tool)
- `STTTool.xcodeproj` — add Sparkle SPM dependency
- `STTTool/Info.plist` — add SUFeedURL, SUPublicEDKey
- `STTTool/STTToolApp.swift` — initialize SPUStandardUpdaterController
- `STTTool/Views/SettingsView.swift` — add "Check for Updates" in General tab
- `.github/workflows/release.yml` — build + sign + publish workflow

### Public repo (stt-tool-releases) — create new
- `README.md`
- `appcast.xml`
- `Casks/stt-tool.rb`
