#!/usr/bin/env zsh

#  pkgAndNotarize.zsh
#  desktoppr
#
#  Builds a universal, signed release binary with SwiftPM, wraps it in a
#  signed installer pkg, and (for the maintainer's team) notarizes it.
#
#  Usage: DEVELOPMENT_TEAM=<team id> ./pkgAndNotarize.zsh
#
#  Requires the Xcode toolchain, plus "Developer ID Application" and
#  "Developer ID Installer" identities for the team in the keychain.

set -euo pipefail

cd "${0:A:h}"
srcroot="$PWD"

: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your Apple Developer team ID}"

pkg_name="desktoppr"
identifier="com.scriptingosx.desktoppr"
min_os_version="12"

# the version lives in Desktoppr.swift
version=$(sed -nE 's/^let version = "([^"]+)".*/\1/p' desktoppr/Desktoppr.swift)
if [[ -z $version ]]; then
  echo "error: could not read version from desktoppr/Desktoppr.swift"
  exit 1
fi

build_dir="$srcroot/build"
artifacts_dir="$build_dir/Artifacts"
pkg_root="$build_dir/pkgroot"
mkdir -p "$artifacts_dir"

component_path="$build_dir/$pkg_name.pkg"
product_path="$artifacts_dir/$pkg_name-$version.pkg"
zip_path="$artifacts_dir/$pkg_name-$version.zip"
log_path="$artifacts_dir/pkg_build.log"

exec > >(tee -a "$log_path") 2>&1

# find signing identities by team ID
app_cert=$(security find-identity -p codesigning -v \
  | awk '/Developer ID Application/ && /'"$DEVELOPMENT_TEAM"'/ {print $2; exit}')
sign_cert=$(security find-identity -p basic -v \
  | awk '/Developer ID Installer/ && /'"$DEVELOPMENT_TEAM"'/ {print $2; exit}')

if [[ -z $app_cert ]]; then
  echo "error: could not find Developer ID Application identity for $DEVELOPMENT_TEAM"
  exit 1
fi
if [[ -z $sign_cert ]]; then
  echo "error: could not find Developer ID Installer identity for $DEVELOPMENT_TEAM"
  exit 1
fi

echo "note: Packaging and Notarizing '$pkg_name', version: $version"
date +"%F %T"
echo "note: Min OS Version:    $min_os_version"
echo "note: Development Team:  $DEVELOPMENT_TEAM"
echo "note: Application cert:  $app_cert"
echo "note: Installer cert:    $sign_cert"
echo

# build a universal release binary
echo "note: building"
swift build -c release --arch arm64 --arch x86_64
bin_path="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$pkg_name"

# sign with hardened runtime and a secure timestamp (required for notarization)
codesign --force --sign "$app_cert" --options runtime --timestamp \
         --identifier "$identifier" "$bin_path"
codesign --verify --strict --verbose=2 "$bin_path"

# stage the pkg payload
rm -rf "$pkg_root"
mkdir -p "$pkg_root/usr/local/bin"
cp "$bin_path" "$pkg_root/usr/local/bin/"

# copy the finished binary to the pkg payload in the examples
cp "$bin_path" "$srcroot/examples/DesktopprManagePkg/payload/usr/local/bin/"

# create the component pkg
echo "note: building component: $component_path"
pkgbuild --root "$pkg_root" \
         --identifier "$identifier" \
         --version "$version" \
         --install-location "/" \
         --min-os-version "$min_os_version" \
         --compression legacy \
         "$component_path"

echo

# create the distribution pkg
echo "note: building distribution pkg: $product_path"
productbuild --package "$component_path" \
             --identifier "$identifier" \
             --version "$version" \
             --sign "$sign_cert" \
             "$product_path"

echo

# clean up component pkg
rm "$component_path"

# only notarize when the development team is the maintainer's
if [[ $DEVELOPMENT_TEAM != "JME5BW3F3R" ]]; then
  echo "note: skipping notarization for team $DEVELOPMENT_TEAM"
  exit 0
fi

# profile name used with `notarytool --store-credentials`
credential_profile="notary-scriptingosx"

echo "note: submitting for notarization"
xcrun notarytool submit "$product_path" \
                 --keychain-profile "$credential_profile" \
                 --wait

echo

xcrun stapler staple "$product_path"

echo

# also create a zip archive of the binary
echo "note: zip archive: $zip_path"
rm -f "$zip_path"
zip "$zip_path" -j "$pkg_root/usr/local/bin/$pkg_name"

echo "note: notarizing zip archive"
xcrun notarytool submit "$zip_path" \
                 --keychain-profile "$credential_profile" \
                 --wait

echo
echo '## Done!'
echo "note: $product_path"
