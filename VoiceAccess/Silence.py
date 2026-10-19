"""Silence the companion from RoboDK without changing the simulation."""

from _AppUtilities import robolink, roboapps
from _voiceaccess.integration import invoke


def ActionSilence():
    with robolink.Robolink() as rdk:
        return invoke(rdk, "silence")


def runmain():
    if roboapps.Unchecked():
        roboapps.Exit()
    else:
        ActionSilence()


if __name__ == "__main__":
    runmain()
