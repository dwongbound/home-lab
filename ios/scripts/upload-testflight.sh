#!/bin/zsh
# Uploads the iPhone/iPad app (the Watch app rides inside) to TestFlight,
# internal testing only, signed in with an App Store Connect API key
# instead of Xcode's account sign-in (which lapses).
#
#   scripts/upload-testflight.sh            # archive the current code, then upload
#   scripts/upload-testflight.sh <archive>  # upload an existing .xcarchive
#
# The key ID and issuer ID come from the environment (ASC_KEY_ID,
# ASC_ISSUER_ID) or from scripts/asc.local (git-ignored), which holds:
#   ASC_KEY_ID=ABC123DEFG
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# The key itself lives at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
# (mode 600). It is never copied into the repo and never printed.
set -euo pipefail

here=${0:A:h}
ios=${here:h}
[[ -f "$here/asc.local" ]] && source "$here/asc.local"
: "${ASC_KEY_ID:?Set ASC_KEY_ID (env or scripts/asc.local)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (env or scripts/asc.local)}"

key="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
if [[ ! -f "$key" ]]; then
  echo "No key at $key" >&2; exit 1
fi
if [[ "$(stat -f %Lp "$key")" != "600" ]]; then
  echo "The key must be readable by you alone: chmod 600 $key" >&2; exit 1
fi

auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$key"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

cd "$ios"
archive=${1:-}
if [[ -z "$archive" ]]; then
  archive="build/testflight/Jarvis.xcarchive"
  rm -rf build/testflight
  xcodegen generate >/dev/null
  xcodebuild archive -scheme Jarvis -destination 'generic/platform=iOS' \
    -archivePath "$archive" "${auth[@]}" DEVELOPMENT_TEAM=7K9BY5Z7B7 | grep -E "error:|ARCHIVE" || true
fi
[[ -d "$archive" ]] || { echo "No archive at $archive" >&2; exit 1; }

version=$(/usr/libexec/PlistBuddy -c 'Print ApplicationProperties:CFBundleVersion' "$archive/Info.plist")
echo "Uploading build $version to TestFlight (internal testing only)…"
xcodebuild -exportArchive -archivePath "$archive" \
  -exportOptionsPlist "$here/ExportOptions-TestFlight.plist" \
  -exportPath "${archive:h}/export" "${auth[@]}"
