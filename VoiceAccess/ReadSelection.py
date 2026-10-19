"""Read the selected item names without automatically reading full details."""

from _AppUtilities import robolink, roboapps
from _voiceaccess.integration import invoke


def ActionReadSelection():
    """Read only the names of selected station items."""

    with robolink.Robolink() as rdk:
        return invoke(rdk, "read-selection")


def runmain():
    if roboapps.Unchecked():
        roboapps.Exit()
    else:
        ActionReadSelection()


if __name__ == '__main__':
    runmain()
