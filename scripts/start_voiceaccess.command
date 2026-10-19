#!/bin/bash
set -euo pipefail
voiceaccess_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
exec "$voiceaccess_root/.venv/bin/python" "$voiceaccess_root/VoiceAccess/OpenVoiceAccess.py"
