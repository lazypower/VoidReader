cask "voidreader" do
  version "CASK_VERSION"
  sha256 "CASK_SHA256"

  url "https://github.com/lazypower/VoidReader/releases/download/v#{version}/VoidReader_v#{version}.dmg"
  name "VoidReader"
  desc "Native macOS markdown viewer with a reader-first philosophy"
  homepage "https://github.com/lazypower/VoidReader"

  depends_on macos: ">= :sonoma"

  app "VoidReader.app"

  zap trash: [
    "~/Library/Preferences/com.voidreader.app.plist",
    "~/Library/Application Support/VoidReader",
  ]
end
