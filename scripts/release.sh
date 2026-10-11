#!/bin/bash
# Builds a signed Keytalk release zip for GitHub and updates the Homebrew cask
# in packaging/homebrew/keytalk.rb with the new version and checksum.
#
# Usage: scripts/release.sh VERSION
#   For example: scripts/release.sh 0.1.0
#
# Every release must be signed with the same identity. macOS ties Keytalk's
# permissions to it, so changing it makes users grant them again.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh VERSION (for example 0.1.0)}"
IDENTITY="${KEYTALK_SIGN_IDENTITY:-Keytalk Release Signing}"
CASK=packaging/homebrew/keytalk.rb

if ! security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
  echo "error: no '$IDENTITY' signing identity in your keychain." >&2
  echo "       Create it once with: scripts/make-signing-cert.sh \"$IDENTITY\"" >&2
  exit 1
fi

KEYTALK_VERSION="$VERSION" KEYTALK_SIGN_IDENTITY="$IDENTITY" ./build.sh
codesign --verify --strict build/Keytalk.app

mkdir -p dist
ZIP="dist/Keytalk-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent build/Keytalk.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" \
          -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"

cat <<DONE

Built $ZIP
SHA-256: $SHA

Next steps:
  1. Commit and tag:   git commit -am "Release $VERSION" && git tag v$VERSION
  2. Push:             git push && git push origin v$VERSION
  3. Create a GitHub release for v$VERSION and attach $ZIP
  4. Copy $CASK to Casks/keytalk.rb in monirz/homebrew-tap, then commit and push
DONE
