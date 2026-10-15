#!/bin/bash

SOURCES_DIR="./Configs"
CONFIG_DIR="./private/Configurations/Configs"
if [ -d "$CONFIG_DIR" ]; then
    cp -a "$CONFIG_DIR/." $SOURCES_DIR
else
    CONFIG_DIR="./public/Configurations/Configs"
    cp -a "$CONFIG_DIR/." $SOURCES_DIR
fi

DESTINATION_INFO_PLIST_FILE="./Resources/RMBT-Info.plist"
INFO_PLIST_FILE="./private/Configurations/RMBT-Info.plist"
if [ -f "$INFO_PLIST_FILE" ]; then
    cp -fr $INFO_PLIST_FILE $DESTINATION_INFO_PLIST_FILE
else
    INFO_PLIST_FILE="./public/Configurations/RMBT-Info.plist"
    cp -fr $INFO_PLIST_FILE $DESTINATION_INFO_PLIST_FILE
fi

DESTINATION_IMAGES_DIR="./Resources/Images.xcassets"
IMAGES_DIR="./private/Configurations/Images.xcassets"
if [ -d "$IMAGES_DIR" ]; then
    cp -a "$IMAGES_DIR/." $DESTINATION_IMAGES_DIR
else
    IMAGES_DIR="./public/Configurations/Images.xcassets"
    cp -a "$IMAGES_DIR/." $DESTINATION_IMAGES_DIR
fi

# Localized Info.plist strings (RMBT-InfoPlist.strings) are brand-specific (private = RTR, public = Open-RMBT):
# they carry the localized CFBundleDisplayName/CFBundleName, so they are synced per locale like RMBT-Info.plist.
# macOS needs a *localized* CFBundleDisplayName to show the branded name (otherwise it falls back to the bundle
# file name "RMBT"). Xcode compiles RMBT-InfoPlist.strings into the bundle's InfoPlist.strings.
INFO_STRINGS_DIR="./private/Configurations/InfoPlist"
if [ ! -d "$INFO_STRINGS_DIR" ]; then
    INFO_STRINGS_DIR="./public/Configurations/InfoPlist"
fi
for LOC in en de; do
    INFO_STRINGS_SRC="$INFO_STRINGS_DIR/$LOC.lproj/RMBT-InfoPlist.strings"
    if [ -f "$INFO_STRINGS_SRC" ]; then
        mkdir -p "./Resources/$LOC.lproj"
        cp -f "$INFO_STRINGS_SRC" "./Resources/$LOC.lproj/RMBT-InfoPlist.strings"
    fi
done
