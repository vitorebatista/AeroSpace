#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

snapshot_version="0.0.0-SNAPSHOT"
build_version="$snapshot_version"
codesign_identity="aerospace-codesign-certificate"
allow_adhoc=0

# The certificate every published release is signed with. macOS stores the app's *designated
# requirement* when the user grants Accessibility or Screen Recording and re-checks it on every
# launch, so this leaf hash is effectively part of the app's identity to TCC: change it and every
# user silently loses both grants. See "Signing identity" in dev-docs/fork-maintenance.md.
release_cert_leaf="bb9c2ac177c6a90115bcf04c071e14cd1004c549"

while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --allow-adhoc) allow_adhoc=1; shift;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

# An ad-hoc signature has no certificate, so the designated requirement degrades to the literal
# binary hash (`cdhash H"..."`), which changes with every build. macOS then treats each update as a
# different app and drops the Accessibility and Screen Recording grants — and the dead TCC entry
# blocks re-granting until the user runs `tccutil reset`. Releases v1.12-v1.15 shipped that way.
# Fail fast rather than spend a full release build producing an artifact that must not be published.
if test "$codesign_identity" == "-" && test "$allow_adhoc" == 0; then
    echo "Refusing to build with an ad-hoc signature (--codesign-identity -)." > /dev/stderr
    echo "It breaks the user's Accessibility and Screen Recording grants on every update." > /dev/stderr
    echo "Sign with 'aerospace-codesign-certificate' (script/create-codesign-certificate.sh)," > /dev/stderr
    echo "or pass --allow-adhoc for a throwaway build that will never be published (CI does that)." > /dev/stderr
    exit 1
fi

#############
### BUILD ###
#############

./script/build-docs.sh
./script/build-shell-completion.sh

./script/generate.sh
./script/check-uncommitted-files.sh
./script/generate.sh --build-version "$build_version" --codesign-identity "$codesign_identity" --generate-git-hash

swift build -c release --arch arm64 --arch x86_64 --product aerospace-edge -Xswiftc -warnings-as-errors # CLI

# todo: make xcodebuild use the same toolchain as swift
# toolchain="$(plutil -extract CFBundleIdentifier raw ~/Library/Developer/Toolchains/swift-6.1-RELEASE.xctoolchain/Info.plist)"
# xcodebuild -toolchain "$toolchain" \
# Unfortunately, Xcode 16 fails with:
#     2025-05-05 15:51:15.618 xcodebuild[4633:13690815] Writing error result bundle to /var/folders/s1/17k6s3xd7nb5mv42nx0sd0800000gn/T/ResultBundle_2025-05-05_15-51-0015.xcresult
#     xcodebuild: error: Could not resolve package dependencies:
#       <unknown>:0: warning: legacy driver is now deprecated; consider avoiding specifying '-disallow-use-new-driver'
#     <unknown>:0: error: unable to execute command: <unknown>

rm -rf .release && mkdir .release

xcode_configuration="Release"
xcodebuild -version
xcodebuild-pretty .release/xcodebuild.log clean build \
    -scheme AeroSpace \
    -destination "generic/platform=macOS" \
    -configuration "$xcode_configuration" \
    -derivedDataPath .xcode-build

git checkout .

cp -r ".xcode-build/Build/Products/$xcode_configuration/AeroSpace-edge.app" .release
cp -r .build/apple/Products/Release/aerospace-edge .release

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospace-edge

################
### VALIDATE ###
################

# Metadata.appintents is emitted by Xcode's App Intents metadata processor from the intents in
# Sources/AeroSpaceApp. It is what makes the commands visible to Shortcuts, Spotlight and Focus
# filters, so its presence here doubles as the build-time check that they were extracted at all.
expected_layout=$(cat <<EOF
.release/AeroSpace-edge.app
.release/AeroSpace-edge.app/Contents
.release/AeroSpace-edge.app/Contents/_CodeSignature
.release/AeroSpace-edge.app/Contents/_CodeSignature/CodeResources
.release/AeroSpace-edge.app/Contents/MacOS
.release/AeroSpace-edge.app/Contents/MacOS/AeroSpace-edge
.release/AeroSpace-edge.app/Contents/Resources
.release/AeroSpace-edge.app/Contents/Resources/default-config.toml
.release/AeroSpace-edge.app/Contents/Resources/Metadata.appintents
.release/AeroSpace-edge.app/Contents/Resources/Metadata.appintents/version.json
.release/AeroSpace-edge.app/Contents/Resources/Metadata.appintents/extract.actionsdata
.release/AeroSpace-edge.app/Contents/Resources/AppIcon.icns
.release/AeroSpace-edge.app/Contents/Resources/Assets.car
.release/AeroSpace-edge.app/Contents/Info.plist
.release/AeroSpace-edge.app/Contents/PkgInfo
EOF
)

if test "$expected_layout" != "$(find .release/AeroSpace-edge.app)"; then
    echo "!!! Expect/Actual layout don't match !!!"
    find .release/AeroSpace-edge.app
    exit 1
fi

check-universal-binary() {
    local architectures
    architectures="$(lipo -archs "$1")"
    if [[ " $architectures " != *" arm64 "* || " $architectures " != *" x86_64 "* ]]; then
        echo "$1 is not a universal binary"
        exit 1
    fi
}

check-contains-hash() {
    hash=$(git rev-parse HEAD)
    if ! strings "$1" | grep --fixed-string "$hash" > /dev/null; then
        echo "$1 doesn't contain $hash"
        exit 1
    fi
}

check-universal-binary .release/AeroSpace-edge.app/Contents/MacOS/AeroSpace-edge
check-universal-binary .release/aerospace-edge

check-contains-hash .release/AeroSpace-edge.app/Contents/MacOS/AeroSpace-edge
check-contains-hash .release/aerospace-edge

codesign -v .release/AeroSpace-edge.app
codesign -v .release/aerospace-edge

# `codesign -v` passes happily on an ad-hoc signature, so it cannot catch the case above on its own
# (this script has no `set -e` either: a failed `codesign -s` would otherwise sail through). Check
# what actually matters to TCC instead — the designated requirement of the shipped artifacts.
check-designated-requirement() {
    local file="$1"
    local dr
    test "$allow_adhoc" == 1 && return 0 # throwaway build, opted in above
    # codesign prints the ad-hoc case commented out ('# designated => cdhash H"..."'), because a
    # hash pin is not a real requirement expression. Strip the marker so both forms are comparable.
    dr="$(codesign -d -r- "$file" 2>/dev/null | sed -n 's/^#* *designated => //p')"

    if [[ "$dr" == *'cdhash H"'* ]]; then
        echo "!!! $file is ad-hoc signed !!!" > /dev/stderr
        echo "    designated => $dr" > /dev/stderr
        echo "Its designated requirement is the binary hash, so it changes with every build." > /dev/stderr
        exit 1
    fi

    if test "$build_version" != "$snapshot_version" &&
        [[ "$dr" != *"certificate leaf = H\"$release_cert_leaf\""* ]]; then
        echo "!!! $file is signed by an unexpected certificate !!!" > /dev/stderr
        echo "    designated => $dr" > /dev/stderr
        echo "    expected    => certificate leaf = H\"$release_cert_leaf\"" > /dev/stderr
        echo "Users' grants are pinned to the requirement previous releases shipped; publishing a" > /dev/stderr
        echo "different one silently revokes them. Restore the backed-up .p12, or update" > /dev/stderr
        echo "release_cert_leaf at the top of this script if the change is deliberate." > /dev/stderr
        exit 1
    fi
}

check-designated-requirement .release/AeroSpace-edge.app
check-designated-requirement .release/aerospace-edge

############
### PACK ###
############

mkdir -p ".release/AeroSpace-edge-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-edge-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-edge-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpace-edge-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-edge-v$build_version/bin" && cp -r aerospace-edge "AeroSpace-edge-v$build_version/bin"
    cp -r AeroSpace-edge.app "AeroSpace-edge-v$build_version"
    zip -r "AeroSpace-edge-v$build_version.zip" "AeroSpace-edge-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospace-edge aerospace-edge-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AeroSpace-edge-v$build_version.zip" \
        --build-version "$build_version"
done
