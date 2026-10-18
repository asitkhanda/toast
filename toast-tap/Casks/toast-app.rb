cask "toast-app" do
  # Reference copy only. The canonical cask is maintained in the external
  # asitkhanda/homebrew-toast-tap repository.
  version "0.4.3"
  sha256 "e16180f63a0a792d2eb9ad347dde70935b8a2f5f4591714f07fde94bd7568ff1"

  url "https://github.com/asitkhanda/toast/releases/download/v#{version}/Toast-#{version}.dmg"
  name "Toast"
  desc "Toast is a menu bar app (no Dock icon) to check your Vercel deployments live. A read-only Vercel personal access token is required to use it."
  homepage "https://toast.asit.space/"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Toast.app"

  auto_updates true

  caveats <<~EOS
    Toast is Developer ID signed and notarized. It should open normally from Applications or Homebrew.
  EOS

  zap trash: [
    "~/Library/Application Support/com.toast.app",
    "~/Library/Preferences/com.toast.app.plist",
  ]
end
