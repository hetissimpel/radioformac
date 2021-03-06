# Radio for Mac

Listen, record and export your favourite radio stations.
All from your menu bar!

![Radio for mac](https://github.com/hetissimpel/radioformac/blob/main/supporting-images/website-screenshot.png)

# What is this?

We are releasing this codebase as open-source under the MIT license. It represents the code as it was when version 1.0.8 was released to the Mac App Store over five years ago.

# Historical & Support

This is presented as a historical artifact. The codebase is not an example of how to write a modern macOS app. It has no tests. It was never written with general consumption in mind.

No support is given due to its historical nature including getting the app to compile with modern compilers and versions of XCode.

The version presented here worked perfectly on macOS 10.15. Changes in App Store guidlines prevented it from being uploaded as it is currently architected. Recordings needed saved to the applications own local storage and not be available in the general "Music" folder where we saved recordings.

# Radio Core

A key part of the codebase is a section we internally called "Radio Core". This was a forked version of a commercially sold license called "RadioTunes SDK". 
The purpose of this code is to wrap the FFMpeg open source library and present its audio packets to the macOS audio subsystem in an efficient way.

The original library was for iOS and he version presented here and embedded in the app has been changed to target the slightly different macOS audio subsystem requirements.

This was created by a now defunct company called Yakamoz Labs and its author [Kemal Taskin](https://github.com/kemaltaskin) has kindly approved the release of this library as part of the overall app.

# FFmpeg

This application relies on FFmpeg library and build scripts are included.

# Contributors

* **Development:** [Damien Glancy](https://github.com/dglancy)
* **Design/UI:** [Jeroen Hermkens](https://github.com/JeroenHermkens)
* **Website:** [Remco Kalf](https://github.com/remcokalf)
* **RadioTunes SDK:** [Kemal Taskin](https://github.com/kemaltaskin)

# Swift Edition

There is an unfinished rewrite of this product in Swift at [Radio - Swift Edition](https://github.com/hetissimpel/radioformac-swift)

# License

This code is released under the MIT License. See LICENSE file for more details. 
This code preserves its original copyright messages on each source file for historical purposes.
