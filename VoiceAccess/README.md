# VoiceAccess for RoboDK — unofficial add-in

VoiceAccess complements RoboDK's existing accessibility with a keyboard-accessible
station tree, item details, and simulation narration. It is an independent project,
not affiliated with, endorsed by, or supported by RoboDK.

The current 0.4.2 preview supports macOS and VoiceOver. Windows/NVDA and Linux/Orca
integration are planned, not implemented. The included native dock is built for
the host's Qt version; the tested configuration is Qt 6.10.1 on macOS x86_64.

Install the `.rdkp` package through RoboDK's Add-in Manager. Open the panel using
the **VA** icon, the VoiceAccess menu, an item's context menu, or Command+Option+V.
Use Command+Up/Down to navigate, Command+Left/Right to collapse/expand, and
Command+L for full item details. Read selection reads names only.

VoiceOver takes priority over the optional local voice. Disable VA with its icon,
the dock close button, or Back to RoboDK to stop simulator playback and suspend
speech and selection following. Enabling it again does not restart playback.
The helper does not connect to or control physical robots.

Original code: MIT, see LICENSE.txt. Bundled API components have their own licenses;
see THIRD_PARTY.txt, LICENSE-ROBODK.txt, and LICENSE-ROBODK-PLUGIN.txt.
