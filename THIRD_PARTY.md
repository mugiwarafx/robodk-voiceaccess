# Third-party components

The MIT license at the repository root covers the original VoiceAccess code.
The components below retain their own copyright notices and licenses.

| Component | Location | License |
| --- | --- | --- |
| RoboDK Python API 6.0.2 | `VoiceAccess/_voiceaccess/vendor/robodk/` | Apache-2.0; see [license](VoiceAccess/LICENSE-ROBODK.txt) and the headers in each file. |
| RoboDK C++ plugin interface headers | `native/dock/vendor/` | MIT; see [license](native/dock/vendor/LICENSE). |

The native dock links dynamically to the Qt frameworks used by the installed
RoboDK application. Qt, RoboDK, macOS, and Apple's speech voices are external
prerequisites; they are not redistributed as part of this repository.

Test stations are generated locally from source. Integration tests load an ABB
robot model from the user's RoboDK installation. RoboDK example stations, robot
model binaries, and the proprietary Components library are not included in the
public source tree or covered by this project's MIT license.

RoboDK is a trademark of its respective owner. VoiceAccess is an independent,
unofficial project and is not affiliated with, endorsed by, or supported by RoboDK.
