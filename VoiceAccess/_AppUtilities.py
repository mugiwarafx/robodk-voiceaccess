"""Shared imports for RoboDK add-in entry points."""

from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from _voiceaccess.bootstrap import load_api

robolink, _ = load_api()
from robodk import roboapps
