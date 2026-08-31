#!/bin/bash
set -e # Exit if one of commands exit with non-zero exit code
set -u # Treat unset variables and parameters other than the special parameters ‘@’ or ‘*’ as an error
set -o pipefail # Any command failed in the pipe fails the whole pipe
# set -x # Print shell commands as they are executed (or you can try -v which is less verbose)

sw_vers -productVersion
# Xcode version affects the target macOS SDK that we compile against + different Xcodes bundle
# different Swift versions. Every runner in the matrix carries Xcode 26; the macos-14 runner, which
# topped out at Xcode 16, was the only reason this ever branched on the OS version.
sudo xcode-select -s "$XCODE_26_DEVELOPER_DIR"
