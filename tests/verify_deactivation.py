"""Disabling VA may stop simulator programs, never controller execution."""
from pathlib import Path
import sys
from unittest.mock import MagicMock
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'VoiceAccess'))
from _voiceaccess.reader import StationReader,rl

rdk=MagicMock();reader=StationReader.__new__(StationReader);reader.rdk=rdk
reader.started_by_us={'ours'};reader.previous_running={'old':1};reader.previous_progress={'old':1}
sim=MagicMock();sim.item=123;sim.Valid.return_value=True;sim.RunType.return_value=rl.PROGRAM_RUN_ON_SIMULATOR;sim.Busy.return_value=True
controller=MagicMock();controller.Valid.return_value=True;controller.RunType.return_value=rl.PROGRAM_RUN_ON_ROBOT
rdk.ItemList.return_value=[sim,controller]
rdk.RunMode.return_value=rl.RUNMODE_RUN_ROBOT
assert reader.deactivate()['stopped_programs']==[]
rdk.ItemList.assert_not_called();sim.Stop.assert_not_called();controller.Stop.assert_not_called()
rdk.RunMode.return_value=rl.RUNMODE_SIMULATE
assert reader.deactivate()['stopped_programs']==['123']
sim.Stop.assert_called_once();controller.Stop.assert_not_called()
assert not reader.started_by_us and not reader.previous_progress and not reader.previous_running
print('Disable stops externally started simulation, clears progress, and excludes controller execution: passed')
