"""Integration checks on a dedicated RoboDK simulator, including live narration events."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "VoiceAccess"))
from station_fixture import create_test_station
from _voiceaccess.reader import StationReader, rl
from _voiceaccess.language import Language
from _voiceaccess.speech import load_rate, load_output_mode, voice_for

if os.environ.get("ROBODK_AI") != "noui":
    raise SystemExit("Run this check with ROBODK_AI=noui to create a dedicated simulator.")


(ROOT/'build/reports/evidence').mkdir(parents=True, exist_ok=True)

with rl.Robolink() as rdk:
    create_test_station(rdk)
    rdk.setRunMode(rl.RUNMODE_SIMULATE)
    rdk.Command("Lang", "en")
    reader = StationReader(rdk)
    snapshot = reader.snapshot()

    def nodes(parent):
        for node in parent:
            yield node
            yield from nodes(node.get("children", []))

    flat = list(nodes(snapshot["nodes"]))
    by_name = {node["name"]: node for node in flat}
    program = rdk.Item("05 Programa de prova", rl.ITEM_TYPE_PROGRAM)
    program_id = reader.key(program)
    assert len(by_name["05 Programa de prova"]["children"]) == 11
    assert snapshot["configuration"]["language"] == "en"
    assert "11 instructions" in reader.detail(program_id)["text"]
    assert "Empty program" in reader.detail(by_name["06 Programa buit"]["id"])["text"]
    decimal_result = reader.detail(by_name["Valors decimals"]["id"])
    decimal_text = decimal_result["text"]
    assert "X -12.5 millimetres" in decimal_text and "Y 25.25 millimetres" in decimal_text
    assert "X minus 12.5 millimetres" in decimal_result["spoken_text"]
    hidden_text = reader.detail(by_name["Objecte ocult"]["id"])["text"]
    assert "Hidden in the scene" in hidden_text
    duplicate_texts = [reader.detail(node["id"])["text"] for node in flat if node["name"] == "Punt repetit"]
    assert len(duplicate_texts) == 2
    assert any("Branca A" in text for text in duplicate_texts)
    assert any("Branca B" in text for text in duplicate_texts)
    tool_text = reader.detail(by_name["Eina Pinça - TCP 80 mm"]["id"])["text"]
    assert "Z 80 millimetres" in tool_text
    robot_text = reader.detail(by_name["Robot ABB IRB 120"]["id"])["text"]
    assert "J6" in robot_text and "Active reference frame" in robot_text and "Active tool" in robot_text

    # Real API names and display text must survive speech normalization intact.
    symbol_name = "ABB IRB 120-3/0.6"
    symbol_item = rdk.AddFrame(symbol_name)
    symbol_snapshot = reader.snapshot()
    symbol_node = next(n for n in nodes(symbol_snapshot["nodes"]) if n["id"] == reader.key(symbol_item))
    assert symbol_node["name"] == symbol_name and symbol_name in symbol_node["label"]
    assert "120 dash 3 slash 0.6" in symbol_node["accessibility_label"]
    symbol_result = reader.detail(reader.key(symbol_item))
    assert symbol_name in symbol_result["text"] and "120 dash 3 slash 0.6" in symbol_result["spoken_text"]
    assert symbol_item.Name() == symbol_name
    rdk.setSelection([symbol_item])
    assert "120 dash 3 slash 0.6" in reader.selection()["spoken_text"]
    captured_id = reader.key(symbol_item)
    rdk.setSelection([program])
    captured = reader.selection([captured_id])
    assert symbol_name in captured["text"] and captured["node_ids"] == [captured_id]
    assert captured["selection_name"] == symbol_name
    assert captured["spoken_selection_name"] == "ABB IRB 120 dash 3 slash 0.6"
    assert "Coordinates relative to" in captured["text"]
    assert "Coordinates" not in captured["spoken_selection_name"]
    multiple = reader.selection([captured_id, program_id])
    assert multiple["selection_name"] == symbol_name + "\n" + program.Name()
    assert reader.selection([])["ids"] == []
    assert reader.selection([])["spoken_selection_name"] == "Nothing is selected in RoboDK."
    try:
        reader.selection(["not-a-pointer"])
    except ValueError:
        pass
    else:
        raise AssertionError("An invalid captured selection was accepted")

    assert Language("ca").spoken("X -12,5; ABB 120-3/0.6") == "X menys 12,5; ABB 120 guió 3 barra 0.6"
    assert Language("es").spoken("X -12,5; ABB 120-3/0.6") == "X menos 12,5; ABB 120 guion 3 barra 0.6"
    assert Language("fr").code == "en"
    punctuation_sample = Language().spoken("ABB IRB 120-3/0.6. X -12.5 millimetres.")
    assert punctuation_sample == "ABB IRB 120 dash 3 slash 0.6. X minus 12.5 millimetres."
    with tempfile.TemporaryDirectory(prefix="voiceaccess-rate-") as directory:
        settings = Path(directory) / "settings.json"
        assert load_rate(settings) == 175
        for value, expected in ((225,225),(20,100),(500,350),("fast",175),(True,175)):
            settings.write_text(json.dumps({"speech_rate":value}))
            assert load_rate(settings) == expected
        settings.write_text("broken JSON")
        assert load_rate(settings) == 175
        assert load_output_mode(settings) == "automatic"
        for mode in ("automatic", "voiceOver", "ownVoice"):
            settings.write_text(json.dumps({"speech_rate":236,"speech_output":mode}))
            assert load_output_mode(settings) == mode and load_rate(settings) == 236

    program.ShowInstructions(False)
    hidden_snapshot = reader.snapshot()
    hidden_program = next(n for n in nodes(hidden_snapshot["nodes"]) if n["id"] == program_id)
    assert len(hidden_program["children"]) == 11
    rdk.setSelection([program])
    assert "11 instructions" in reader.selection()["text"]
    program.ShowInstructions(True)
    assert "Instruction 5 of 11" in reader.detail(f"instruction:{program_id}:4")["text"]

    events = []
    selected_program = reader.resolve(program_id)
    original_run = selected_program.RunCode
    run_calls = []
    def counted_run(*args, **kwargs):
        run_calls.append(time.monotonic())
        return original_run(*args, **kwargs)
    selected_program.RunCode = counted_run
    assert reader.simulate(program_id)["started"]
    assert reader.simulate(program_id)["started"] is False
    assert len(run_calls) == 1, "Double activation started the program twice"
    deadline = time.monotonic() + 20
    while program.Busy() or reader.previous_running:
        assert time.monotonic() < deadline, "Simulation timed out"
        events.extend(reader.poll()["events"])
        time.sleep(0.08)
    assert any(event["kind"] == "start" for event in events)
    assert any(event["kind"] == "move" and "Linear move" in event["text"] for event in events)
    assert any(event["kind"] == "move" and "Treball" in event["text"] for event in events)
    assert any(event["kind"] == "end" for event in events)

    reader.simulate(program_id)
    reader.poll()
    reader.stop()
    deadline = time.monotonic() + 5
    while program.Busy():
        assert time.monotonic() < deadline
        time.sleep(0.03)

    for identifier in [by_name["06 Programa buit"]["id"], by_name["Robot ABB IRB 120"]["id"]]:
        try:
            reader.simulate(identifier)
        except ValueError:
            pass
        else:
            raise AssertionError("An invalid simulation target was accepted")
    rdk.setRunMode(rl.RUNMODE_QUICKVALIDATE)
    try:
        reader.simulate(program_id)
    except ValueError:
        pass
    else:
        raise AssertionError("A non-simulation run mode was accepted")
    rdk.setRunMode(rl.RUNMODE_SIMULATE)

    # Switch only this dedicated simulator, then detect the live language change.
    rdk.Command("Lang", "es")
    reader.last_language_check = 0
    assert reader.poll()["needs_refresh"]
    spanish = reader.snapshot()
    assert spanish["configuration"]["language"] == "es"
    assert spanish["configuration"]["voice"] == voice_for("es")
    assert "Contiene 11 instrucciones" in reader.detail(program_id)["text"]
    assert "X -12,5 milímetros" in reader.detail(by_name["Valors decimals"]["id"])["text"]
    assert spanish["configuration"]["ui"]["Read details"] == "Leer detalles"
    rdk.Command("Lang", "en")
    reader.last_language_check = 0
    assert reader.poll()["needs_refresh"]
    english = reader.snapshot()
    assert english["configuration"]["language"] == "en"
    assert english["configuration"]["voice"] == voice_for("en")

    # A real nested program: thirteen calls to a one-instruction child. The
    # displayed/spoken counter must stay with the parent, never become 1 of 1.
    reader.poll()  # Drain the previously stopped test program.
    child = rdk.AddProgram("Progress child", rdk.Item("Robot ABB IRB 120", rl.ITEM_TYPE_ROBOT))
    child.Pause(500)
    parent = rdk.AddProgram("Progress Main", rdk.Item("Robot ABB IRB 120", rl.ITEM_TYPE_ROBOT))
    for _ in range(13):
        parent.RunInstruction(child.Name(), rl.INSTRUCTION_CALL_PROGRAM)
    reader.snapshot()
    parent_id, child_id = reader.key(parent), reader.key(child)
    assert child_id in reader.program_calls[parent_id]
    parent.setRunType(rl.PROGRAM_RUN_ON_SIMULATOR)
    child.setRunType(rl.PROGRAM_RUN_ON_SIMULATOR)
    rdk.setSimulationSpeed(1)
    parent.RunCode()
    nested_progress, nested_events, progress_fixture = [], [], None
    deadline = time.monotonic() + 20
    while parent.Busy() or reader.previous_running:
        assert time.monotonic() < deadline, "Nested simulation timed out"
        poll = reader.poll()
        nested_events.extend(poll["events"])
        for progress in poll["progress"]:
            assert progress["program_id"] == parent_id and progress["total"] == 13
            if progress["step"] is not None:
                nested_progress.append(progress)
                assert f'{progress["step"]} of 13' in progress["spoken_text"]
                if progress["step"] == 5:
                    progress_fixture = poll
        time.sleep(0.05)
    assert {p["step"] for p in nested_progress} == set(range(1,14))
    assert any(p["active_program_id"] == child_id for p in nested_progress)
    assert all(event["program_id"] == parent_id for event in nested_events)
    assert sum(event["kind"] == "start" for event in nested_events) == 1
    assert sum(event["kind"] == "end" for event in nested_events) == 1
    assert "13 of 13" not in nested_events[-1]["spoken_text"]
    assert any("13 of 13" in event["spoken_text"] for event in nested_events[:-1])
    assert "13 of 13" in nested_events[-1]["progress_text"]
    assert nested_events[-1]["text"] == "Progress Main: execution finished or stopped."
    assert progress_fixture is not None

    child_env = os.environ.copy()
    child_env.pop("ROBODK_AI", None)  # Attach workers to the dedicated instance.
    worker = subprocess.run(
        [sys.executable, str(ROOT/"VoiceAccess/_voiceaccess/bridge.py"), "--port", str(rdk.PORT)],
        input='{"id":1,"command":"snapshot"}\n{"id":2,"command":"detail","item_id":"missing"}\n',
        text=True, capture_output=True, timeout=15, check=True, env=child_env,
    )
    responses = [json.loads(line) for line in worker.stdout.splitlines()]
    assert len(responses) == 2 and responses[0]["ok"] and not responses[1]["ok"]

    with tempfile.TemporaryDirectory(prefix="voiceaccess-native-") as directory:
        native_report = Path(directory) / "report.json"
        fixture_file = Path(directory) / "progress.json"
        fixture_file.write_text(json.dumps(progress_fixture))
        completion_file = Path(directory) / "completion.json"
        completion_file.write_text(json.dumps(nested_events[-1]))
        subprocess.run([
            str(ROOT/"VoiceAccess/_native/VoiceAccess.app/Contents/MacOS/VoiceAccess"),
            "--python", sys.executable, "--bridge", str(ROOT/"VoiceAccess/_voiceaccess/bridge.py"),
            "--port", str(rdk.PORT), "--self-test", str(native_report),
            "--settings-path", str(Path(directory)/"settings.json"),
            "--progress-fixture", str(fixture_file),
            "--completion-fixture", str(completion_file),
        ], check=True, capture_output=True, timeout=20, env=child_env)
        native = json.loads(native_report.read_text())
        assert native["panel_language"] == "en" and native["robodk_language"] == "en"
        assert native["speech_rate_controls_and_persistence_checked"]
        assert native["speech_rate_accessibility_role"] == "AXSlider"
        assert native["speech_rate_accessibility_label"] == "Speech rate"
        assert native["symbol_row_display_preserved"]
        assert "dash" in native["symbol_row_accessibility_value"] and "slash" in native["symbol_row_accessibility_value"]
        assert "Read details" in native["button_labels"] and "Test voice" in native["button_labels"]
        assert "Back to RoboDK" in native["button_labels"]
        assert native["accessory_activation_policy"] and native["auxiliary_panel"] and native["hide_on_deactivate"]
        assert native["voiceover_routing_matrix_checked"]
        assert native["voiceover_blocks_explicit_own_voice_checked"]
        assert native["panel_accepts_main_focus"]
        assert native["outline_public_and_attribute_rows_match"]
        assert native["outline_ax_selection_updates_model_checked"]
        assert native["outline_plain_arrow_navigation_checked"]
        assert native["global_item_navigation_shortcuts_checked"]
        assert native["focus_tree_shortcut_checked"]
        assert native["expand_collapse_shortcuts_checked"]
        assert native["non_root_fold_preserves_focus_and_navigation"]
        assert native["collapsed_state_preserved_after_filter_refresh"]
        assert native["context_simulation_available_for_program_only"]
        assert "Expand item" in native["tree_context_menu_labels"]
        assert "Collapse item" in native["tree_context_menu_labels"]
        assert "Simulate program" in native["tree_context_menu_labels"]
        assert native["completion_counter_visible_without_repeating_speech_checked"]
        assert native["outline_accessible_rows"] == native["rendered_row_count"]
        assert native["speech_output_accessibility_label"] == "Speech output"
        assert native["execution_progress_accessibility_label"] == "Execution progress"
        assert "Step 5 of 13" in native["execution_progress_text"]
        assert "Step 5 of 13" in native["execution_progress_accessibility_value"]

    report = {
        "scope": "dedicated simulator; user RoboDK window untouched",
        "robodk_version": rdk.Version(),
        "station": snapshot["station_name"],
        "station_item_count": snapshot["item_count"],
        "program_instructions_read": 11,
        "instructions_read_when_hidden_in_robodk": True,
        "decimal_description": decimal_text,
        "duplicate_target_descriptions": duplicate_texts,
        "tool_description": tool_text,
        "robot_description": robot_text,
        "hidden_object_description": hidden_text,
        "simulation_events": events,
        "simulation_stop_verified": True,
        "double_activation_started_one_simulation": True,
        "invalid_simulation_requests_rejected": True,
        "json_worker_protocol_verified": True,
        "language_tracks_connected_robodk": ["en", "es", "en"],
        "english_voice": english["configuration"]["voice"],
        "spanish_voice": spanish["configuration"]["voice"],
        "symbol_name_unchanged": symbol_node["name"],
        "symbol_accessibility_label": symbol_node["accessibility_label"],
        "symbol_spoken_description": symbol_result["spoken_text"],
        "negative_coordinate_spoken_description": decimal_result["spoken_text"],
        "speech_rate_settings_validation_checked": True,
        "native_panel_checks": native,
        "captured_roboDK_selection_read_after_selection_changed": captured,
        "nested_program_counter": {
            "parent": "Progress Main", "parent_total": 13, "child_instruction_count": 1,
            "observed_steps": sorted({p["step"] for p in nested_progress}),
            "parent_counter_preserved_during_child": True,
            "events": nested_events,
            "captured_step_5": progress_fixture,
        },
        "manual_voiceover_validation_required": True,
    }
    (ROOT/"build/reports/verificacio-voiceaccess.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print("VOICEACCESS_CHECKS_PASSED",flush=True)
