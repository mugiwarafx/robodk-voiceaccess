# Contributing

VoiceAccess is an unofficial project focused on making RoboDK station data and
simulation progress easier to use with screen readers. The current implementation
is a macOS preview. NVDA on Windows and Orca on Linux are planned.

## Report an accessibility issue

Include the operating system, RoboDK and Qt versions, screen-reader version,
interface language, and exact keys or actions used. For VoiceOver navigation,
include the Quick Nav state and whether you were interacting with a group.
Describe what was spoken, what you expected, and whether keyboard focus and the
selected item agreed.

A small station or a script that reproduces the issue is more useful than a large
project. Remove license details, private station content, and personal paths from
screenshots and logs before sharing them. The [manual testing guide](docs/accessibility.md)
lists useful checks.

## Develop a change

1. Follow [the development guide](docs/development.md) to build locally.
2. Keep the Python station-reading logic separate from platform-specific UI and
   screen-reader integration.
3. Run the checks relevant to the change. Use a dedicated RoboDK simulator for
   integration tests.
4. For UI or speech changes, describe the manual screen-reader checks performed
   and distinguish them from automated checks.

Keep changes focused. Preserve accessible labels, keyboard actions, focus after
collapse, and the rule that our own speech stays silent while VoiceOver is active.
Disabling VA must suspend automatic reading, discard pending speech, and stop
simulator playback without restarting it when the panel is re-enabled.

Do not add real-robot control to this helper. Preserve the simulator-mode and
program-run-type checks in playback and deactivation code.

## Source and generated files

Commit source, documentation, tests, and required third-party license notices.
Build outputs, add-in metadata, `.rdkp` packages, robot/station binaries, test
reports, audio, and local development history belong in ignored directories.
The build and package scripts generate the installable artifacts.

The package version lives in `VoiceAccess/AppConfig.ini`. Native library and Swift
module names are derived from it. A loaded Swift module remains in the host for
its lifetime: bump the version for a live update, or restart your development
instance before reusing the same module name. Do not overwrite a running test
station to validate a UI change.
