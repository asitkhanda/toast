cask "toast-app" do
  version "0.4.0"
  sha256 "c3c2ab45874893f9e2ad87587a615a7fb5475a57d0033d0db6e16677644b60a7"

  url "https://github.com/asitkhanda/toast/releases/download/v#{version}/Toast-#{version}.dmg"
  name "Toast"
  desc "Toast is a menu bar app (no Dock icon) to check your Vercel deployments live. A read-only Vercel personal access token is required to use it."
  homepage "https://toast.asit.space/"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "Toast.app"

  auto_updates true

  caveats <<~EOS
    Toast is Developer ID signed and notarized. Double-click to open after
    copying to Applications. If macOS still warns on an older download,
    right-click Toast in Applications → Open → Open once.
  EOS

  zap trash: [
    "~/Library/Application Support/com.toast.app",
    "~/Library/Preferences/com.toast.app.plist",
  ]
end
