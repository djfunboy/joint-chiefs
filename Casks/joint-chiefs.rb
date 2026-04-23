# Homebrew cask formula for Joint Chiefs.
#
# This file is a placeholder until the first signed/notarized DMG ships.
# Before publishing:
#
#   1. Build and notarize the release DMG (see distribution/release-process.md).
#   2. Upload it to the GitHub release at v#{version} with filename Joint-Chiefs.dmg.
#   3. Run `shasum -a 256 build/Joint-Chiefs.dmg` and paste the hash into `sha256`.
#   4. Either open a PR against Homebrew/homebrew-cask, or push to a personal tap
#      (`djfunboy/homebrew-jointchiefs`) so users can run
#      `brew tap djfunboy/jointchiefs && brew install --cask joint-chiefs`.

cask "joint-chiefs" do
  version "0.1.0"
  sha256 "fb83ddc66c3da45574fddfcf88e0b8796b01035fcf95dd9f8702f6d53ac163f9"

  url "https://github.com/djfunboy/joint-chiefs/releases/download/v#{version}/Joint-Chiefs.dmg",
      verified: "github.com/djfunboy/joint-chiefs/"
  name "Joint Chiefs"
  desc "Multi-model AI code review orchestrator"
  homepage "https://jointchiefs.ai/"

  livecheck do
    url "https://jointchiefs.ai/appcast.xml"
    strategy :sparkle
  end

  auto_updates true
  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "Joint Chiefs.app"

  # Symlink the three CLI binaries from inside the bundle into /opt/homebrew/bin
  # so `jointchiefs`, `jointchiefs-mcp`, and `jointchiefs-keygetter` resolve from
  # any shell without the user running the wizard's install step. The setup app
  # detects these and skips its silent install on launch.
  binary "#{appdir}/Joint Chiefs.app/Contents/Resources/jointchiefs"
  binary "#{appdir}/Joint Chiefs.app/Contents/Resources/jointchiefs-mcp"
  binary "#{appdir}/Joint Chiefs.app/Contents/Resources/jointchiefs-keygetter"

  zap trash: [
    "~/Library/Application Support/Joint Chiefs",
    "~/Library/Preferences/com.jointchiefs.setup.plist",
  ]
end
