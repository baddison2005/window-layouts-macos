cask "window-layouts" do
  version "1.3.0"
  sha256 "2587a9a7f0de7265ef4b0d44af2b68bf786923045b86262fc73dcc11038601be"

  url "https://github.com/baddison2005/window-layouts-macos/releases/download/v#{version}/Window-Layouts-#{version}-macOS.dmg",
      verified: "github.com/baddison2005/window-layouts-macos/"
  name "Window Layouts"
  desc "Create and apply custom layouts to application windows"
  homepage "https://github.com/baddison2005/window-layouts-macos"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Window Layouts.app"

  zap trash: [
    "~/Library/Application Support/Window Layouts",
    "~/Library/Caches/com.astrobrett.WindowLayouts",
    "~/Library/HTTPStorages/com.astrobrett.WindowLayouts",
    "~/Library/Preferences/com.astrobrett.WindowLayouts.plist",
    "~/Library/Saved Application State/com.astrobrett.WindowLayouts.savedState",
  ]
end
