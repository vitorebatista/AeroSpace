#!/bin/bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

build_version="0.0.0-SNAPSHOT"
codesign_identity="aerospace-codesign-certificate"
while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

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
