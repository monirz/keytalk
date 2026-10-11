cask "keytalk" do
  version "0.1.0"
  sha256 "76c76a14970d6eddb83385f36f0a734eea01a86d718f1a02e8e9eafa530b2d1d"

  url "https://github.com/monirz/keytalk/releases/download/v#{version}/Keytalk-#{version}.zip"
  name "Keytalk"
  desc "Hold a key, speak, and paste the text into any app"
  homepage "https://github.com/monirz/keytalk"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :monterey

  app "Keytalk.app"

  uninstall quit: "com.monirz.keytalk"

  zap trash: "~/Library/Preferences/com.monirz.keytalk.plist"

  caveats <<~EOS
    Keytalk isn't notarized by Apple yet, so macOS blocks it the first time:
      1. Open Keytalk. When macOS says it can't verify Keytalk, click Done.
      2. In System Settings > Privacy & Security, click Open Anyway next to
         the Keytalk message, and then confirm.
    You only need to do this once. Upgrades keep working.
  EOS
end
