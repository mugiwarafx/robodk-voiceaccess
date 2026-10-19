"""Generate the integration fixture locally; no RoboDK model binaries are redistributed."""

import argparse
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "VoiceAccess"))
from _voiceaccess.bootstrap import load_api

rl, rm = load_api()


def create_test_station(rdk, robot_file=None):
    model = robot_file or os.environ.get("VOICEACCESS_TEST_ROBOT")
    if model is None:
        model = Path(rl.getPathRoboDK("Library")) / "06-Pick and Place/Parts/ABB-IRB-120-3-0-6.robot"
    model = Path(model)
    if not model.is_file():
        raise FileNotFoundError(
            "The integration fixture requires the ABB IRB 120 model from your RoboDK installation. "
            "Set VOICEACCESS_TEST_ROBOT to its .robot file."
        )
    station = rdk.AddStation("VoiceAccess - Prova VoiceOver")
    rdk.setRunMode(rl.RUNMODE_SIMULATE)
    rdk.Render(False)
    try:
        base = rdk.AddFrame("01 Base del robot", station)
        robot = rdk.AddFile(str(model), base)
        robot.setName("Robot ABB IRB 120")
        tool = robot.AddTool(rm.transl(0, 0, 80), "Eina Pinça - TCP 80 mm")
        table = rdk.AddFrame("02 Referència Taula", station)
        plane = rdk.AddFrame("Pla superior de la taula", table)
        plane.setPose(rm.transl(250, -225, 200))
        reference = rdk.AddFrame("03 Referència Peça", station)
        reference.setPose(rm.transl(350, -150, 250))
        robot.setPoseFrame(reference)
        robot.setPoseTool(tool)
        home_joints = [0, -30, 30, 0, 45, 0]
        approach_joints = [10, -25, 35, 5, 40, 10]

        def target(name, parent, joints, joint_target=False):
            robot.setPoseFrame(parent)
            robot.setJoints(joints)
            item = rdk.AddTarget(name, parent, robot)
            item.setPose(robot.Pose())
            item.setJoints(joints)
            if joint_target:
                item.setAsJointTarget()
            else:
                item.setAsCartesianTarget()
            return item

        home = target("Inici", reference, home_joints, True)
        approach = target("Aproximació", reference, approach_joints)
        work = rdk.AddTarget("Treball", reference, robot)
        work.setJoints(approach_joints)
        work.setPose(approach.Pose() * rm.transl(0, 0, 15))
        work.setAsCartesianTarget()
        cases = rdk.AddFrame("04 Casos de lectura", station)
        for name in ("Branca A", "Branca B"):
            branch = rdk.AddFrame(name, cases)
            target("Punt repetit", branch, home_joints).setVisible(False)
        numbers = rdk.AddFrame("Valors decimals", cases)
        numbers.setPose(rm.Pose(-12.5, 25.25, 90, 0, 0, 0))
        long_name = rdk.AddFrame(
            "Referència amb nom llarg per comprovar si VoiceOver llegeix el text complet sense truncar-lo", cases
        )
        long_name.setVisible(False)
        # An original asymmetric marker mesh exercises object visibility without
        # depending on third-party shape libraries or redistributing CAD assets.
        vertices = [
            [0, 0, 0], [17, 0, 0], [3, 11, 6],
            [0, 0, 0], [3, 11, 6], [0, 2, 19],
            [17, 0, 0], [0, 2, 19], [3, 11, 6],
        ]
        hidden = rdk.AddShape(rm.Mat(vertices).tr())
        hidden.setParent(cases)
        hidden.setName("Objecte ocult")
        hidden.setVisible(False)
        robot.setPoseFrame(reference)
        robot.setPoseTool(tool)
        program = rdk.AddProgram("05 Programa de prova", robot)
        program.setRunType(rl.PROGRAM_RUN_ON_SIMULATOR)
        program.setPoseFrame(reference)
        program.setPoseTool(tool)
        program.setSpeed(100)
        program.RunInstruction("Inici de la prova de lectura", rl.INSTRUCTION_COMMENT)
        program.MoveJ(home)
        program.MoveJ(approach)
        program.setSpeed(50)
        program.MoveL(work)
        program.Pause(300)
        program.MoveJ(home)
        program.RunInstruction("Fi de la prova de lectura", rl.INSTRUCTION_COMMENT)
        program.ShowInstructions(True)
        empty = rdk.AddProgram("06 Programa buit", robot)
        empty.setRunType(rl.PROGRAM_RUN_ON_SIMULATOR)
        robot.setJoints(home_joints)
        rdk.setSelection([robot])
    finally:
        rdk.Render(True)
    return station


if __name__ == "__main__":
    if os.environ.get("ROBODK_AI") != "noui":
        raise SystemExit("Use ROBODK_AI=noui to generate the fixture in a dedicated simulator.")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--robot", type=Path, help="Local ABB IRB 120 .robot model")
    parser.add_argument("--output", type=Path, default=ROOT / "build/fixtures/VoiceAccess-Test.rdk")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with rl.Robolink() as rdk:
        station = create_test_station(rdk, args.robot)
        rdk.Save(str(args.output.resolve()), station)
    print(args.output)
