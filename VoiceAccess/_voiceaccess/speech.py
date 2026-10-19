"""Local speech configuration shared by the panel and ReadSelection action."""

from functools import lru_cache
import json
import math
from pathlib import Path
import re
import subprocess

DEFAULT_RATE = 175
MIN_RATE = 100
MAX_RATE = 350
SETTINGS_PATH = Path.home() / "Library/Application Support/RoboDKVoiceAccess/settings.json"


def load_rate(path=None):
    try:
        value = json.loads((path or SETTINGS_PATH).read_text())["speech_rate"]
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
            return DEFAULT_RATE
        return round(max(MIN_RATE, min(MAX_RATE, value)))
    except (OSError, ValueError, KeyError, TypeError):
        return DEFAULT_RATE


def load_output_mode(path=None):
    try:
        mode = json.loads((path or SETTINGS_PATH).read_text()).get("speech_output", "automatic")
        return mode if mode in ("automatic", "voiceOver", "ownVoice") else "automatic"
    except (OSError, ValueError, TypeError, AttributeError):
        return "automatic"


@lru_cache(maxsize=1)
def installed_voices():
    try:
        output = subprocess.check_output(["/usr/bin/say", "-v", "?"], text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return {}
    result = {}
    for line in output.splitlines():
        match = re.match(r"^(.*?)\s+([a-z]{2}_[A-Z]{2})\s+#", line)
        if match:
            result[match.group(1).strip()] = match.group(2)
    return result


def voice_for(language):
    voices = installed_voices()
    preferred = {"en": ("Samantha", "Daniel"), "ca": ("Montse",), "es": ("Mónica", "Paulina")}
    for name in preferred.get(language, ()):
        if name in voices:
            return name
    return next((name for name, locale in voices.items() if locale.startswith(language + "_")), None)


def configuration(language):
    return {
        "robodk_language": language.robodk_code,
        "language": language.code,
        "language_fallback": language.code != language.robodk_code.split("-")[0],
        "voice": voice_for(language.code),
        "speech_rate": load_rate(),
        "speech_output": load_output_mode(),
        "speech_rate_min": MIN_RATE,
        "speech_rate_max": MAX_RATE,
        "voice_test": language.spoken(language.t("Voice test. Model ABB IRB 120-3/0.6. X -12.5 millimetres.")),
        "ui": language.ui(),
    }
