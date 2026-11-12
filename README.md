# Here comes the `desktoppr`!

![](https://img.shields.io/github/v/release/scriptingosx/desktoppr)&nbsp;![](https://img.shields.io/github/downloads/scriptingosx/desktoppr/latest/total)&nbsp;![](https://img.shields.io/badge/macOS-14%2B-success)&nbsp;![](https://img.shields.io/github/license/scriptingosx/desktoppr)

A simple command line tool which can read and set the desktop picture/wallpaper. Credit for the name to [Neil Martin](https://macadmins.slack.com/archives/C19MR7EM9/p1536586211000100).

Note: Apple used to call the macOS background image 'desktop picture' until macOS 13 Ventura, when they changed to be the same as in iOS: 'wallpaper'. This documentation might use either term.

I have written a few blog posts that describe different use strategies for setting a desktop picture:

- [Using desktoppr in a managed environment](https://scriptingosx.com/2024/01/using-desktoppr-in-a-managed-environment/)
- [Building a LaunchD Installer pkg for desktoppr (and other tools)](https://scriptingosx.com/2024/07/building-a-launchd-installer-pkg-for-desktoppr-and-other-tools/)
- [Strategies to using desktoppr](https://scriptingosx.com/2020/03/strategies-to-using-desktoppr/)
- [Random Desktop Background with desktoppr](https://scriptingosx.com/2020/04/random-desktop-background-color-with-desktoppr/)

## Getting and setting the current desktop picture/wallpaper

You can read the current desktop picture/wallpaper with:

```
$ desktoppr picture
/Library/Desktop Pictures/Sierra.jpg
```

and set the desktop picture with

```
$ desktoppr picture "/Library/Desktop Pictures/BoringBlueDesktop.png"
```

Run `desktoppr --help` or `desktoppr <subcommand> --help` for all subcommands and options.

When the path is a path to a folder, the system will rotate the wallpaper through all the image files in that folder. The default rotation time is 30 minutes and can be changed in the Wallpaper settings pane. `desktoppr` cannot change the frequency.

```
$ desktoppr picture "/Library/Desktop Pictures/My Wallpapers/"
```

When you have multiple displays, `desktoppr` will list all desktop pictures:

```
$ desktoppr picture
/Library/Desktop Pictures/HotStepper.jpg
/Library/Desktop Pictures/LyricalGangster.jpg
/Library/Desktop Pictures/MrOfficer.jpg
```

When you pass a file `desktoppr` will set it as the desktop picture for _all_ screens:

```
$ desktoppr picture "/Library/Desktop Pictures/NaahNananah.jpg"
$ desktoppr picture
/Library/Desktop Pictures/NaahNananah.jpg
/Library/Desktop Pictures/NaahNananah.jpg
/Library/Desktop Pictures/NaahNananah.jpg
```

You can also set the desktop for a specific screen: (index starts at zero)

```
$ desktoppr picture --screen 0 "/Library/Desktop Pictures/HotStepper.jpg"
$ desktoppr picture --screen 1 "/Library/Desktop Pictures/LyricalGangster.jpg"
$ desktoppr picture --screen 2 "/Library/Desktop Pictures/MrOfficer.jpg"
```

`desktoppr` can also control the image scaling and background color for the desktop picture.

The scale and color settings will be set for all screens.

Use the `scale` verb to control how the desktops are scaled. It can have the values `fill` (default), `stretch`, `center`, or `fit`.

```
$ desktoppr scale center
```

You can pass a hex string for the background color:

```
$ desktoppr color 000000      # black background
$ desktoppr color FFFFFF      # white background
$ desktoppr color FF0000      # red background
```

Setting the wallpaper, scale and/or color are separate commands.

Note: setting the background color does not work in macOS 14.x. See [issue #22](https://github.com/scriptingosx/desktoppr/issues/22). This was fixed by Apple in macOS 15.4.

## Setting the picture for all Spaces

macOS keeps a separate wallpaper for every Space (desktop), and `desktoppr` normally only changes the current Space's. To also set the picture on every existing Space, and on Spaces you create later, add `--all-spaces`:

```
$ desktoppr picture --all-spaces "/Library/Desktop Pictures/BoringBlueDesktop.png"
```

`--all-spaces` only applies when setting a picture on all screens, so it needs a picture and cannot be combined with `--screen main` or a screen index. It works by copying the new setting within macOS's private wallpaper store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`), which Apple does not document and may change. `desktoppr` waits up to 15 seconds for macOS to record the new picture and exits with an error if that does not happen. It then restarts `WallpaperAgent` (launchd relaunches it right away), which macOS needs to apply the edited store.

## Using `desktoppr` in scripts

When you run multiple `desktoppr` commands in sequence in a script, the subsequent commands might not "take." Insert a `sleep 1` command in between to allow the process managing the wallpaper to "catch up."

```
desktoppr picture "/Library/Desktop Pictures/HotStepper.jpg"
sleep 1
desktoppr scale fit
sleep 1
desktoppr color 000000
```

When you desktoppr in a script, you have to ensure that the `PATH` contains `/usr/local/bin` or include the entire path to the binary:

```
/usr/local/bin/desktoppr picture "/Library/Desktop Pictures/BoringBlueDesktop.png"
```

Since the `desktoppr` tool changes user space settings, you need to pay attention that it runs as the user. A LaunchAgent or a solution like [`outset`](https://github.com/macadmins/outset) is a good choice to manage this. Alternatively, you can [run the command as the current user from a root script](https://scriptingosx.com/2020/08/running-a-command-as-another-user/).

## Downloading the wallpaper image file

When you give a URL to an image file as the argument, `desktoppr` will download the file from the URL and set it as the wallpaper.

```
$ desktoppr https://raw.githubusercontent.com/scriptingosx/desktoppr/profile/examples/BoringBlueDesktop.png
```

The downloaded file will be stored in `~/Library/Application Support/desktoppr/`.

When the download fails, the wallpaper will not be changed. If the downloaded file is not an image file, the wallpaper will revert to the system default.

## Managing the desktop picture/wallpaper with a profile

When you run `desktoppr` with the `manage` verb, it will read the settings from the `com.scriptingosx.desktoppr` preference domain. You can set these settings with the `defaults` command or, preferably, by pushing a configuration profile from an MDM server.

The idea is to run `desktoppr manage` with a LaunchAgent plist at login and/or at regular intervals. You can find [a sample LaunchAgent plist here](examples/com.scriptingosx.desktopprmanage.plist). The sample LaunchAgent will run `desktoppr manage` at login and every three hours (10800 sec). You can build a pkg that installs the desktoppr binary, the LaunchAgent plist and an image file very early in the deployment workflow and then desktoppr sets the desktop background when the user reaches the desktop for the first time.

For Ventura and higher, binaries and applications run by LaunchAgents need to be approved with a `com.apple.servicemanagement` profile so they appear as managed in the login items section in Settings.app. The [sample configuration profile](examples/desktoppr-profile.mobileconfig) contains those settings, as well.


`desktoppr` uses the following profile keys:

#### `picture` (type: `string`)

The path to the image file for the desktop picture/wallpaper. The same image will be set for all screens.

When the value starts with `http://` or `https://` desktoppr will interpret this as a URL and attempt to download a file and set that file as the desktop picture/wallpaper. The downloaded file will be stored in `~/Library/Application Support/desktoppr/`. You can have desktoppr verify the downloaded image file by providing  a `sha256` checksum.

#### `sha256` (type: `string`)

This sha256 checksum will be used to verify the downloaded image file. If the checksum from the downloaded file does not match the value of this key, the desktop picture/wallpaper will not be changed.

You can generate the sha256 checksum of the image file with `shasum -a 256 <filepath>`

#### `color` (type: `string`)

This string will be interpreted as a six-digit hex code and set as the background color.

#### `scale` (type: `string`)

One of `fill` (default), `stretch`, `center`, or `fit`. This controls the scaling behavior of the image.

#### `setOnlyOnce` (type: boolean, default: `false`)

When set to `true`, `desktoppr manage` will not re-set the desktop picture/wallpaper if the last picture `desktoppr manage` set was the same. Use this to set the desktop image/wallpaper once from a configuration profile but allow the user to change it afterward. Even when `desktoppr manage` runs frequently, it should only re-set the desktop picture/wallpaper when the setting in the configuration profile changes.

When set to `false`, `desktoppr manage` will re-apply the managed settings every time.

#### `allSpaces` (type: boolean, default: `false`)

When set to `true`, `desktoppr manage` also sets the picture for every Space, as `desktoppr picture --all-spaces` does on the command line.

The examples have [a sample defaults plist with keys](examples/defaults.plist) and [a sample configuration profile](examples/desktoppr-profile.mobileconfig).

## Download

You can get the code for `desktoppr` on my Github page and an installer in the [Releases](https://github.com/scriptingosx/desktoppr/releases). The installer pkg will install the binary in `/usr/local/bin`. Alternatively, a brew cask exists, so you could install it using `brew install --cask desktoppr` if you have [Homebrew](https://brew.sh) installed.

`desktoppr` requires macOS 14 or later.

## Development

Build with `swift build` or `nix build`.

Run the tests with `swift test --disable-xctest`, or `run-tests` in the Nix devshell, which adds the flag for you because XCTest is not available under Nix.
`nix flake check` also runs the tests along with the formatters and other checks.

Building requires the Swift 6 toolchain (the package uses Swift 6 language mode) and macOS 14 or later.
CI runs `nix flake check` on every pull request.
