# Flow for Messenger

A reverse-engineered source code project based on Flow v1.0 for Messenger.

This repository contains the recovered source code and changes made to address issues reported by the jailbreak and sideloading communities. It is intended for code review, further development and rebuilding.

## Overview

The project focuses on three areas:

- Understanding the original Flow v1.0 implementation.
- Fixing reported crashes and broken features.
- Providing source code that can be reviewed and modified.

The fixes target specific issues found during reverse engineering. They do not guarantee compatibility with every version of Messenger or iOS.

## Source layout

| Path | Description |
|---|---|
| `Tweak.xm` | Main tweak source code. Contains hooks, feature logic and fixes for the identified issues. |
| `Makefile` | Theos build configuration. |
| `build_dylib.sh` | Build script for the dynamic library. |
| `Flow.plist` | Tweak configuration and app filter. |
| `layout/` | Additional resources and files used by the project. |

## Fixes

The following issues have been addressed in the original source code.

| Issue | Cause | Fix |
|---|---|---|
| Crashes on newer iOS versions and in LiveContainer | The original code contains anti-debugging system calls. | Removed the identified system calls and related checks. |
| Crashes when other dynamic libraries are present | The original code checks for unexpected libraries and can terminate the process. | Disabled the identified library checks and abort paths. |
| Dependence on RootHide-specific libraries | The original code expects RootHide libraries and calls a RootHide-specific function. | Updated the relevant dependency handling and bypassed the RootHide-specific call where required. |
| Group `@mentions` stop working when the typing indicator is disabled | The text update hook skips a call required for Messenger's text handling. | Updated the hook to preserve mention handling while keeping the typing indicator disabled. |
| Flow settings become difficult to open after hiding tabs | Removing tab items can leave the tab bar and tab controller out of sync. | Added a long-press gesture on the bottom tab bar to open Flow settings directly. |
| Quick Emoji and action sheets crash on iPad | The action sheet does not provide the required popover presentation information. | Added the missing popover source view and source rectangle. |
| Anonymous story viewing may still mark stories as seen | Messenger calls an additional method when a story is fully displayed. | Added a hook to block that method when anonymous story viewing is enabled. |

These changes are based on the issues identified during reverse engineering and community reports. They still need to be tested against the relevant Messenger and iOS versions.

## Technical notes

### Anti-debugging and library checks

The original binary contains system calls and library checks that can terminate Messenger under certain conditions. The source changes remove the identified calls and disable the related termination paths.

### Text input and group mentions

The text update hook has been changed to preserve Messenger's handling of group mentions when the typing indicator is disabled.

### Tab bar and settings

A long-press gesture provides a direct way to open Flow settings when hidden tabs make the original navigation difficult to use.

### Story viewing

An additional story display method is handled when anonymous story viewing is enabled. Other tracking methods may still exist in future Messenger versions.

### iPad action sheets

The action sheet presentation code now provides the view and position information required for popover presentation on iPad.

## Compatibility

Compatibility depends on the iOS version, Messenger version and the environment in which the tweak is built and tested.

Messenger updates may change internal methods or behaviour used by the tweak. Further changes may be required to maintain compatibility.

## Credits

- **Original project:** [dayanch96/Flow](https://github.com/dayanch96/Flow)
- **Community reports:** [r/jailbreak](https://www.reddit.com/r/jailbreak/) and [r/sideloaded](https://www.reddit.com/r/sideloaded/)

This project is based on the original Flow tweak. Credit for the original work belongs to its author.

## Disclaimer

This project is not affiliated with or endorsed by Meta or the original Flow author.

It is provided for research, code review and educational purposes. The source code and its changes are provided without a guarantee that every feature will work on every device or app version.
