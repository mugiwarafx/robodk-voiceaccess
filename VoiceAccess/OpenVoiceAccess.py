"""Toggle the unofficial VoiceAccess reader from RoboDK."""

from _AppUtilities import robolink, roboapps
from _voiceaccess.integration import invoke
from _voiceaccess.toolbar import panel_visible


def ActionOpenVoiceAccess():
    """Toggle the reader, ignoring feedback from toolbar state synchronization."""

    with robolink.Robolink() as rdk:
        if roboapps.Checked():
            roboapps.KeepChecked()
            if panel_visible(rdk.PORT):
                return
        elif roboapps.Unchecked():
            if not panel_visible(rdk.PORT):
                return
            return invoke(rdk, "hide")
        return invoke(rdk, "show")


def runmain():
    ActionOpenVoiceAccess()


if __name__ == '__main__':
    runmain()
