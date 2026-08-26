cask "toast-app" do
  # Reference copy only. The canonical cask is maintained in the external
  # asitkhanda/homebrew-toast-tap repository.
  version "0.4.2"
  sha256 "d2e97fb049c5bede2d586919761e4f57228e54ddd6812dbf6fe26a43a3cd9c39"

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
