#!/bin/bash
# Creates the self-signed code signing certificate that release builds are signed with, as an
# alternative to the Keychain Access clicks in dev-docs/development.md. macOS will show a couple of
# authorization dialogs (trust settings + private key access) — approving them is the point.
#
# The identity must stay the same forever: it is what makes macOS keep the user's Accessibility
# grant across updates. Back up the .p12 this prints, and see the "Signing identity" section of
# dev-docs/fork-maintenance.md.
set -euo pipefail

name="${1:-aerospace-codesign-certificate}"
keychain="$HOME/Library/Keychains/login.keychain-db"
out_dir="${2:-${AEROSPACE_CODESIGN_DIR:-$HOME/.config/aerospace-codesign}}"

if security find-identity -v -p codesigning | grep --fixed-string "$name" > /dev/null; then
    echo "Identity '$name' already exists — nothing to do."
    exit 0
fi

mkdir -p "$out_dir"
chmod 700 "$out_dir"
cert="$out_dir/$name.pem"
key="$out_dir/$name.key.pem"
p12="$out_dir/$name.p12"

# LibreSSL (/usr/bin/openssl) writes a 3DES-encrypted .p12, which `security import` reads.
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 7300 -nodes \
    -keyout "$key" -out "$cert" -subj "/CN=$name" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"
# `security import` rejects a .p12 with an empty password ("MAC verification failed"), so give it one.
p12_password="$(/usr/bin/openssl rand -base64 18)"
/usr/bin/openssl pkcs12 -export -out "$p12" -inkey "$key" -in "$cert" -name "$name" \
    -passout "pass:$p12_password"
printf '%s\n' "$p12_password" > "$p12.password"
chmod 600 "$key" "$p12" "$p12.password"

security import "$p12" -k "$keychain" -P "$p12_password" -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$cert"
# Importing with -T grants codesign access to the key. If a later `codesign -s` ever fails with
# errSecInternalComponent, widen it by hand (it asks for your login password):
#     security set-key-partition-list -S apple-tool-:,apple:,codesign: -s -l "$name" "$keychain"

echo
security find-identity -v -p codesigning
echo
echo "Private key + certificate: $out_dir"
echo "BACK UP $p12 (password in $p12.password) — losing it costs every user one more re-grant."
