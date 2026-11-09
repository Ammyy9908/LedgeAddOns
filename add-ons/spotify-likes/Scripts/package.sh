#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
binary_directory="$(swift build -c release --show-bin-path)"
output_directory="${1:-$PWD/.build/addons}"
mkdir -p "$output_directory"
output_directory="$(cd "$output_directory" && pwd)"
package="$output_directory/SpotifyLikes.ledgeaddon"
mkdir -p "$package/Assets"
cp "$binary_directory/SpotifyLikes" "$package/SpotifyLikes"
cp addon.json "$package/addon.json"
cp Assets/Icon.png "$package/Assets/Icon.png"
codesign --force --sign - "$package/SpotifyLikes"
echo "$package"
