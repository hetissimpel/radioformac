## Modified by Yakamoz Labs ##

These scripts are taken from https://github.com/gabriel/ffmpeg-iphone-build and modified to suit our needs.
RadioTouch uses FFmpeg for the mms protocol and for decoding wma audio streams. If you want you can enable
support for other codecs by modifying the ffmpeg-conf file.

## Gas preprocessor
Uses a gas preprocessor via http://github.com/mansr/gas-preprocessor. Download the gas-preprocessor.pl script 
from this website and place it under /usr/sbin/.

## Scripts
- `build-ffmpeg`: Build script for FFmpeg; Run this first and then `combine-libs`
- `combine-libs`: Creates universal binaries; Runs lipo -create on each of the FFmpeg static libs

## Build FFmpeg
1) Run the ./build-ffmpeg script. This will download the 2.0 version of FFmpeg and build static libraries for
the armv7, armv7s and i386 platforms.
2) Run the ./combine-libs script to create universal FFmpeg static libraries. These libraries will be placed in 
the dist-uarch folder.

