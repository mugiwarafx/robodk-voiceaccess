# Building and development

The native implementation currently targets macOS. Build and test it with a Qt
SDK that matches the Qt version used by your RoboDK host. The configuration tested
for this preview is RoboDK 6.0.6.26900 with Qt 6.10.1 on macOS x86_64.

## Requirements

- macOS, Python 3.10 or newer, and Xcode command-line tools with Swift and Clang.
- RoboDK with its Add-in Manager enabled.
- Qt 6.10.1 development tools, including `qmake`, matching the host architecture.

The Python SDK is vendored with its license. It and the standard library provide
the Python runtime dependencies; no additional Python package is required.

Set the Qt location and build:

```sh
python3 -m venv .venv
export VOICEACCESS_QT="/path/to/Qt/6.10.1/macos"
make build PYTHON=.venv/bin/python
make package PYTHON=.venv/bin/python
```

The add-in is written to `dist/VoiceAccess-0.4.2.rdkp`. Install it through RoboDK's
Add-in Manager. Builds are ad-hoc signed for local use; they are not notarized
macOS releases. The build targets macOS 13 or later, but validation so far has
been on the development machine, not across all supported OS versions.

`VOICEACCESS_ARCH` can explicitly select the target architecture. Match it to the
RoboDK process and Qt SDK. Apple Silicon builds have not yet been validated.
The build fails early when `qmake` reports an incompatible Qt version.

## Development installation

With RoboDK running and the binaries built:

```sh
make install-development PYTHON=.venv/bin/python
```

This links the checkout into the user's RoboDK Addins directory and enables only
VoiceAccess. It writes a local wrapper under `build/development-addin/` and records
the operation under `build/reports/`. It does not create a Git commit or publish a
package. An existing installation linked to a different checkout is left alone.

The native dock and Swift module are loaded into RoboDK. A loaded Swift module
stays mapped for the host's lifetime. For an updated native build, use a new
version in `VoiceAccess/AppConfig.ini` so the library/module names change, or
restart a dedicated development instance before loading a replacement with the
same name. Build outputs are replaced atomically to protect already mapped files.

If the compatible native plugin cannot load, the add-in can open the standalone
AppKit companion. Both routes use the same station-reading and speech logic.

## Tests

Run API-independent checks, native accessibility structure tests, IPC tests, and
speech-queue tests:

```sh
make unit PYTHON=.venv/bin/python
```

The speech tests generate local audio files; they do not play them. Reports and
audio remain under ignored `build/reports/`.

Integration tests require a local ABB IRB 120 model from the RoboDK library. Set
`VOICEACCESS_TEST_ROBOT` if it is installed elsewhere:

```sh
export VOICEACCESS_TEST_ROBOT="/path/to/ABB-IRB-120-3-0-6.robot"
make integration PYTHON=.venv/bin/python
```

Each test creates a dedicated simulator through `ROBODK_AI=noui`, builds the
fixture in memory, and closes that instance afterward. Tests exercise program
narration, deactivation, sidebar sizing, and native loading. They do not attach
to the user's working station or control real hardware.

To generate a local station for manual testing:

```sh
make fixture PYTHON=.venv/bin/python
```

This writes `build/fixtures/VoiceAccess-Test.rdk`. The generator uses the installed
robot model and original marker geometry. No robot model or proprietary shape
library is distributed in this repository. Fixture item names intentionally
include Catalan text, duplicate names, and long strings to exercise accessibility
and localization.

## Packaging and source layout

`VoiceAccess/AppConfig.ini` is the source of the package version. The build scripts
derive binary/module names and add-in metadata from it. `package_addin.py` creates
the OPC relationships, manifest, and installable ZIP package without an external
packaging tool. Metadata identifies VoiceAccess contributors as the publisher
and explicitly describes the project as unofficial. `make package` also checks
the archive's metadata, assets, license notices, and executable permissions.

| Path | Purpose |
| --- | --- |
| `VoiceAccess/` | Add-in actions, settings, Python backend, and vendored SDK. |
| `native/` | AppKit UI, speech queue, accessibility rows, and Qt dock host. |
| `scripts/` | Build, packaging, and development-install tools. |
| `tests/` | API-independent checks, native tests, and generated-station integration tests. |
| `docs/` | Public documentation and a panel-only screenshot. |
| `build/`, `dist/` | Ignored outputs and packages. |

Generated metadata, native binaries, reports, station files, and local history are
excluded from version control. Preserve third-party copyright and license files
when updating vendored SDK components.
