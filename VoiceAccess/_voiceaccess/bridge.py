"""JSON-lines worker for the macOS accessibility panel."""

import argparse
import contextlib
import json
import os
from pathlib import Path
import sys
import signal

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from _voiceaccess.bootstrap import load_api
from _voiceaccess.reader import StationReader
from _voiceaccess.toolbar import sync_toolbar


def serve(port):
    rl, _ = load_api()
    with contextlib.redirect_stdout(sys.stderr):
        rdk = rl.Robolink(port=port, args=["-API_NODELAY"])
    reader = StationReader(rdk)
    toolbar_owned = False
    try:
        for line in sys.stdin:
            request = {}
            try:
                request = json.loads(line)
                with contextlib.redirect_stdout(sys.stderr):
                    command = request.get("command")
                    if command == "snapshot":
                        result = reader.snapshot()
                    elif command == "detail":
                        result = reader.detail(request["item_id"])
                    elif command == "selection":
                        result = reader.selection(request.get("item_ids"))
                    elif command == "poll":
                        result = reader.poll()
                    elif command == "simulate":
                        result = reader.simulate(request["item_id"])
                    elif command == "stop":
                        result = reader.stop()
                    elif command == "deactivate":
                        result = reader.deactivate()
                    elif command == "panel-state":
                        result = sync_toolbar(rdk, bool(request["visible"]), os.getppid())
                        toolbar_owned = True
                    else:
                        raise ValueError(reader.language.t("Unknown VoiceAccess action."))
                response = {"id": request.get("id"), "ok": True, "result": result}
            except Exception as error:
                response = {"id": request.get("id"), "ok": False, "error": str(error), "spoken_error": reader.language.spoken(str(error))}
            try:
                print(json.dumps(response, ensure_ascii=False, allow_nan=False), flush=True)
            except BrokenPipeError:
                # The companion can close while an API response is in flight.
                # Avoid a second flush error at interpreter shutdown.
                with open(os.devnull, "w") as sink:
                    os.dup2(sink.fileno(), sys.stdout.fileno())
                break
    finally:
        if toolbar_owned:
            with contextlib.suppress(Exception):
                reader.deactivate()
            with contextlib.suppress(Exception):
                sync_toolbar(rdk, False, os.getppid())
        rdk.Disconnect()


if __name__ == "__main__":
    def terminate(_signal, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, terminate)
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=20500)
    serve(parser.parse_args().port)
