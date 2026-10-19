"""Read station semantics through the API, independently of the native tree UI."""

import math
import re
import time
from .bootstrap import load_api
from .language import Language, robodk_language
from .speech import configuration

rl, rm = load_api()

TYPES = {
    1: "Station", 2: "Robot", 3: "Reference frame", 4: "Tool", 5: "Object",
    6: "Target", 7: "Curve", 8: "Program", 9: "Instruction",
    10: "Python program", 11: "Machining project", 17: "Folder",
    18: "Robot arm", 19: "Camera", 20: "Item", 21: "External axes",
    22: "Notes",
}


def number(value, language=None):
    language = language or Language()
    value = float(value)
    if not math.isfinite(value):
        return language.t("not available")
    if abs(value) < 0.005:
        value = 0.0
    result = f"{value:.2f}".rstrip("0").rstrip(".")
    return result if language.code == "en" else result.replace(".", ",")


def coordinates(pose, language):
    xyzrxryrz = rm.Pose_2_TxyzRxyz(pose)
    return [
        language.t("Position") + ": " + "; ".join(f"{axis} {number(v, language)} " + language.t("millimetres") for axis, v in zip("XYZ", xyzrxryrz[:3])) + ".",
        language.t("Orientation Rx, Ry, Rz") + ": " + "; ".join(f"{axis} {number(v * 180 / math.pi, language)} " + language.t("degrees") for axis, v in zip(("Rx", "Ry", "Rz"), xyzrxryrz[3:])) + ".",
    ]


class StationReader:
    def __init__(self, rdk):
        self.rdk = rdk
        self.language = Language(robodk_language(rdk))
        self.last_language_check = time.monotonic()
        self.items = {}
        self.programs = []
        self.previous_running = {}
        self.previous_progress = {}
        self.program_instructions = {}
        self.program_calls = {}
        self.station_id = ""
        self.started_by_us = set()
        self.last_simulation_start = float("-inf")

    @staticmethod
    def key(item):
        return str(item.item)

    def resolve(self, identifier):
        item = self.items.get(str(identifier))
        if item is None or not item.Valid():
            raise ValueError(self.language.t("The item has changed or no longer exists. Refresh the station."))
        return item

    def path(self, item):
        parts, seen = [], set()
        while item.Valid() and self.key(item) not in seen:
            seen.add(self.key(item))
            parts.append(item.Name())
            item = item.Parent()
        return list(reversed(parts))

    def instruction(self, program, index):
        t = self.language.t
        count = program.InstructionCount()
        if not 0 <= index < count:
            raise ValueError(t("This instruction no longer exists. Refresh the program."))
        name, kind, movement, joint_target, pose, joints = program.Instruction(index)
        call_name = None
        if kind == rl.INS_TYPE_CODE:
            parameters = program.setParam(index)
            if isinstance(parameters, dict) and parameters.get("Behavior") == rl.INSTRUCTION_CALL_PROGRAM:
                call_name = parameters.get("Code", "").strip()
        if kind == rl.INS_TYPE_MOVE:
            match = re.search(r"\((.*)\)", name)
            destination = match.group(1) if match else name
            short = t("Linear move to {destination}" if movement == rl.MOVE_TYPE_LINEAR else "Joint move to {destination}", destination=destination)
        else:
            short = name
        text = [t("Instruction {index} of {count} in program {name}.", index=index+1, count=count, name=program.Name()), short + "."]
        if kind == rl.INS_TYPE_MOVE and pose is not None and not joint_target:
            text.append(t("Coordinates relative to the reference frame used by this instruction."))
            text.extend(coordinates(pose, self.language))
        return self.language.output({
            "id": f"instruction:{self.key(program)}:{index}",
            "name": name, "kind": t("Instruction"), "type": 9,
            "program_id": self.key(program), "index": index,
            "instruction_type": kind, "call_name": call_name,
            "label": t("{index} of {count}. {description}", index=index+1, count=count, description=short),
            "short": short, "text": "\n".join(text), "children": [],
        })

    def snapshot(self):
        self.language = Language(robodk_language(self.rdk))
        self.last_language_check = time.monotonic()
        t = self.language.t
        station = self.rdk.ActiveStation()
        if not station.Valid():
            raise ValueError(t("No station is open in RoboDK."))
        new_station = self.key(station)
        if self.station_id != new_station:
            self.previous_running = {}
            self.previous_progress = {}
        self.station_id = new_station
        self.items, self.programs = {}, []
        self.program_instructions = {}
        count = 0

        def node(item):
            nonlocal count
            kind = item.Type()
            if kind == rl.ITEM_TYPE_INSTRUCTION:
                return None
            identifier = self.key(item)
            self.items[identifier] = item
            count += 1
            name = item.Name()
            result = {"id": identifier, "name": name, "kind": t(TYPES.get(kind, "Item")), "type": kind}
            result["label"] = f"{result['kind']}. {name}"
            if kind == rl.ITEM_TYPE_PROGRAM:
                self.programs.append(item)
                size = item.InstructionCount()
                result["label"] += ". " + t("{count} instructions", count=size)
                result["children"] = [self.instruction(item, i) for i in range(size)]
                self.program_instructions[identifier] = result["children"]
            else:
                result["children"] = [value for child in item.Childs() if (value := node(child)) is not None]
            return result

        tree = node(station)
        names = {}
        for program in self.programs:
            names.setdefault(program.Name(), []).append(self.key(program))
        self.program_calls = {}
        for key, instructions in self.program_instructions.items():
            self.program_calls[key] = {
                names[info["call_name"]][0]
                for info in instructions
                if info.get("call_name") in names and len(names[info["call_name"]]) == 1
            }
        return self.language.output({
            "station_id": self.station_id, "station_name": station.Name(),
            "nodes": [tree], "item_count": count, "program_count": len(self.programs),
            "message": t("Station {name}. {items} items and {programs} programs.", name=station.Name(), items=count, programs=len(self.programs)),
            "selection": [self.key(item) for item in self.rdk.Selection()],
            "host_pid": int(self.rdk.Command("MainProcess_ID")),
            "configuration": configuration(self.language),
        })

    def detail(self, identifier):
        t = self.language.t
        identifier = str(identifier)
        if identifier.startswith("instruction:"):
            _, parent, index = identifier.split(":")
            return self.instruction(self.resolve(parent), int(index))
        item = self.resolve(identifier)
        kind, name = item.Type(), item.Name()
        lines = [f"{t(TYPES.get(kind, 'Item'))}. {name}.", t("Location") + ": " + " > ".join(self.path(item)) + "."]
        if kind in (rl.ITEM_TYPE_FRAME, rl.ITEM_TYPE_TARGET, rl.ITEM_TYPE_OBJECT, rl.ITEM_TYPE_TOOL):
            if kind == rl.ITEM_TYPE_TOOL:
                lines.append(t("TCP relative to the robot flange."))
            else:
                parent = item.Parent()
                lines.append(t("Coordinates relative to {name}.", name=parent.Name() if parent.Valid() else t("the station")))
            lines.extend(coordinates(item.PoseTool() if kind == rl.ITEM_TYPE_TOOL else item.Pose(), self.language))
            lines.append(t("Visible in the scene." if item.Visible() else "Hidden in the scene."))
        if kind == rl.ITEM_TYPE_TARGET:
            lines.append(t("Joint target." if item.isJointTarget() else "Cartesian target."))
        if kind in (rl.ITEM_TYPE_ROBOT, rl.ITEM_TYPE_ROBOT_AXES, rl.ITEM_TYPE_ROBOT_ARM):
            values = item.Joints().list()
            lines.append(t("Model joint values") + ": " + "; ".join(f"J{i+1}: {number(v, self.language)}" for i, v in enumerate(values)) + ".")
            lines.append(t("Joint units depend on the model kinematics."))
            for link_type, title in ((rl.ITEM_TYPE_FRAME, "Active reference frame"), (rl.ITEM_TYPE_TOOL, "Active tool")):
                linked = item.getLink(link_type)
                if linked.Valid():
                    lines.append(f"{t(title)}: {linked.Name()}.")
            lines.append(t("TCP position relative to the active reference frame."))
            lines.extend(coordinates(item.Pose(), self.language))
        if kind == rl.ITEM_TYPE_PROGRAM:
            size = item.InstructionCount()
            lines.append(t("Contains {count} instructions.", count=size) if size else t("Empty program, no instructions."))
            robot = item.getLink(rl.ITEM_TYPE_ROBOT)
            if robot.Valid():
                lines.append(t("Associated robot") + f": {robot.Name()}.")
            lines.append(t("Running." if item.Busy() else "Idle."))
            lines.append(t("Configured for the simulator." if item.RunType() == rl.PROGRAM_RUN_ON_SIMULATOR else "Configured to run on the controller."))
            if size:
                lines.append(t("Expand this program in the VoiceAccess tree to read its instructions."))
        if kind in (rl.ITEM_TYPE_STATION, rl.ITEM_TYPE_FOLDER):
            lines.append(t("Contains {count} direct children.", count=len(item.Childs())))
        if kind == rl.ITEM_TYPE_PROGRAM_PYTHON:
            lines.append(t("Reading and executing Python code is outside this prototype's scope."))
        return self.language.output({"id": identifier, "name": name, "kind": t(TYPES.get(kind, "Item")), "type": kind, "text": "\n".join(lines)})

    def selection(self, identifiers=None):
        if identifiers is None:
            selected = self.rdk.Selection()
        else:
            if not isinstance(identifiers, list) or not all(isinstance(key, str) and key.isdecimal() and int(key) > 0 for key in identifiers):
                raise ValueError(self.language.t("The item has changed or no longer exists. Refresh the station."))
            selected = [rl.Item(self.rdk, int(key)) for key in identifiers]
            if any(not item.Valid(True) for item in selected):
                raise ValueError(self.language.t("The item has changed or no longer exists. Refresh the station."))
        if not selected:
            message = self.language.t("Nothing is selected in RoboDK.")
            return self.language.output({"ids": [], "node_ids": [], "text": message,
                                         "selection_name": message, "spoken_selection_name": self.language.spoken(message)})
        descriptions, node_ids = [], []
        for item in selected:
            identifier = self.key(item)
            kind = item.Type()
            if identifier not in self.items and kind != rl.ITEM_TYPE_INSTRUCTION:
                self.snapshot()
            if identifier in self.items:
                descriptions.append(self.detail(identifier)["text"])
                node_ids.append(identifier)
            elif kind == rl.ITEM_TYPE_INSTRUCTION:
                parent = item.Parent()
                children = parent.Childs()
                index = next((i for i, child in enumerate(children) if child == item), -1)
                if parent.Type() == rl.ITEM_TYPE_PROGRAM and index >= 0:
                    descriptions.append(self.instruction(parent, index)["text"])
                    node_ids.append(f"instruction:{self.key(parent)}:{index}")
                else:
                    descriptions.append(self.language.t("Instruction") + ". " + item.Name())
                    node_ids.append(self.key(parent))
        names = "\n".join(item.Name() for item in selected)
        return self.language.output({"ids": [self.key(item) for item in selected], "node_ids": node_ids,
                                     "selection_name": names, "spoken_selection_name": self.language.spoken(names),
                                     "text": "\n\n".join(descriptions) or self.language.t("No description is available for this selection.")})

    def poll(self):
        if time.monotonic() - self.last_language_check > 2:
            self.last_language_check = time.monotonic()
            if robodk_language(self.rdk) != self.language.robodk_code:
                return {"needs_refresh": True, "events": []}
        t = self.language.t
        station = self.rdk.ActiveStation()
        if not station.Valid():
            self.previous_running = {}
            self.previous_progress = {}
            return {"station_id": "", "selection": [], "events": [], "progress": [], "running": []}
        identifier = self.key(station)
        if identifier != self.station_id:
            return {"station_id": identifier, "selection": [], "events": [], "needs_refresh": True}
        events, running, states = [], {}, {}
        for program in self.programs:
            if not program.Valid() or not program.Busy():
                continue
            key = self.key(program)
            index = program.InstructionSelect()
            name = program.Name()
            running[key] = index
            size = program.InstructionCount()
            # The program can finish between Busy() and InstructionSelect().
            # Never turn -1 into a fictitious 'step 0'.
            info = self.instruction(program, index) if 0 <= index < size else None
            states[key] = {"name": name, "index": index, "total": size, "info": info}

        def descendants(key):
            found, pending = set(), list(self.program_calls.get(key, ()))
            while pending:
                child = pending.pop()
                if child == key or child in found:
                    continue
                found.add(child)
                pending.extend(self.program_calls.get(child, ()))
            return found

        reachable = {key: descendants(key) for key in states}
        roots = [key for key in states if not any(key in children for other, children in reachable.items() if other != key)]
        # A cyclic call graph cannot supply a unique outer caller. Keep a
        # deterministic representative instead of losing its progress entirely.
        covered = set().union(*(reachable[key] | {key} for key in roots)) if roots else set()
        for key in states:
            if key not in covered:
                roots.append(key)
                covered.update(reachable[key] | {key})

        progress = {}
        for key in roots:
            state = states[key]
            info = state["info"]
            label = t("Running {name}.", name=state["name"])
            if info is not None:
                label = t("{name}. Step {index} of {count}. {instruction}.", name=state["name"], index=state["index"]+1, count=state["total"], instruction=info["name"])
            # Prefer the deepest active descendant for movement context, while
            # the counter remains that of the outer program (e.g. Main / 13).
            group = [child for child in states if child == key or child in reachable[key]]
            leaf = max(group, key=lambda child: sum(child in reachable[parent] for parent in group))
            leaf_info = states[leaf]["info"]
            current = {
                "program_id": key, "program_name": state["name"],
                "index": state["index"], "step": state["index"]+1 if info is not None else None,
                "total": state["total"], "instruction": info["name"] if info is not None else "",
                "active_program_id": leaf, "active_program_name": states[leaf]["name"],
                "active_index": states[leaf]["index"], "text": label,
            }
            progress[key] = current
            previous = self.previous_progress.get(key)
            root_changed = previous is None or previous["index"] != state["index"]
            leaf_changed = previous is None or (previous["active_program_id"], previous["active_index"]) != (leaf, states[leaf]["index"])
            kind, description = None, ""
            if previous is None:
                kind = "start"
                description = t("Running {name}.", name=state["name"])
            elif root_changed:
                kind = "move" if leaf_info is not None and leaf_info["instruction_type"] == rl.INS_TYPE_MOVE else "step"
            elif leaf_changed and leaf_info is not None and leaf_info["instruction_type"] == rl.INS_TYPE_MOVE:
                kind = "move"
            if kind:
                if info is not None:
                    short = leaf_info["short"] if kind == "move" else info["short"]
                    if kind == "start":
                        description += " " + t("{index} of {count}. {description}", index=state["index"]+1, count=state["total"], description=short) + "."
                    else:
                        description = t("{name}. {index} of {count}. {description}.", name=state["name"], index=state["index"]+1, count=state["total"], description=short)
                events.append({**current, "kind": kind, "text": description})
        for key, previous in self.previous_progress.items():
            if key in progress:
                continue
            text = t("{name}: execution finished or stopped.", name=previous["program_name"])
            progress_text = text
            if previous["step"] is not None:
                progress_text = t("{name}. {index} of {count}. Execution finished or stopped.", name=previous["program_name"], index=previous["step"], count=previous["total"])
            events.append({**previous, "kind": "end", "text": text, "progress_text": progress_text,
                           "progress_spoken_text": self.language.spoken(progress_text)})
            self.started_by_us.discard(key)
        self.previous_running = running
        self.previous_progress = progress
        return self.language.output({"station_id": identifier, "selection": [self.key(i) for i in self.rdk.Selection()], "events": events, "progress": list(progress.values()), "running": list(running)})

    def simulate(self, identifier):
        t = self.language.t
        if str(identifier).startswith("instruction:"):
            identifier = str(identifier).split(":")[1]
        program = self.resolve(identifier)
        if program.Type() != rl.ITEM_TYPE_PROGRAM:
            raise ValueError(t("Select a simulation program in the VoiceAccess tree."))
        if self.rdk.RunMode() != rl.RUNMODE_SIMULATE:
            raise ValueError(t("RoboDK must be in simulation mode to use this button."))
        if any(p.RunType() != rl.PROGRAM_RUN_ON_SIMULATOR for p in self.programs if p.Valid()):
            raise ValueError(t("Some programs are configured for the controller. This prototype only starts stations with every program in simulation mode."))
        if any(item.Type() == rl.ITEM_TYPE_PROGRAM_PYTHON for item in self.items.values() if item.Valid()):
            raise ValueError(t("VoiceAccess playback requires a station without Python programs. Use VoiceAccess-VoiceOver.rdk."))
        if program.InstructionCount() == 0:
            raise ValueError(t("The program is empty. There are no movements to execute."))
        if time.monotonic() - self.last_simulation_start < 0.75 or any(p.Valid() and p.Busy() for p in self.programs):
            return self.language.output({"started": False, "text": t("A simulation is already starting or running.")})
        program.setRunType(rl.PROGRAM_RUN_ON_SIMULATOR)
        self.rdk.setSimulationSpeed(0.25)
        program.RunCode()
        self.last_simulation_start = time.monotonic()
        self.started_by_us.add(self.key(program))
        return self.language.output({"started": True, "text": t("Simulating {name} at reduced speed to make narration easier to follow.", name=program.Name())})

    def stop(self):
        if self.rdk.RunMode() != rl.RUNMODE_SIMULATE:
            raise ValueError(self.language.t("This action is only available in the simulator."))
        for key in list(self.started_by_us):
            item = self.items.get(key)
            if item is not None and item.Valid():
                item.Stop()
        self.started_by_us.clear()
        return self.language.output({"text": self.language.t("Requested a stop for the simulation started from VoiceAccess.")})

    def deactivate(self):
        """Stop current simulator programs when the user disables VoiceAccess."""
        stopped = []
        if self.rdk.RunMode() == rl.RUNMODE_SIMULATE:
            # Include programs started from RoboDK itself, not only this reader.
            for item in self.rdk.ItemList(rl.ITEM_TYPE_PROGRAM):
                if item.Valid() and item.RunType() == rl.PROGRAM_RUN_ON_SIMULATOR and item.Busy():
                    item.Stop()
                    stopped.append(self.key(item))
        self.started_by_us.clear()
        self.previous_running = {}
        self.previous_progress = {}
        return {"deactivated": True, "stopped_programs": stopped}
