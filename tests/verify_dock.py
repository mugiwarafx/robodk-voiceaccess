"""Load the real Qt plugin in a separate host, attached to a dedicated simulator."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'VoiceAccess'))
from station_fixture import create_test_station
from _voiceaccess.integration import DOCK_LIBRARY
from _voiceaccess.bootstrap import load_api
rl, _ = load_api()
if os.environ.get('ROBODK_AI') != 'noui':
    raise SystemExit('Use ROBODK_AI=noui for the isolated integration check.')
(ROOT/'build/reports/evidence').mkdir(parents=True, exist_ok=True)

with rl.Robolink() as rdk, tempfile.TemporaryDirectory(prefix='voiceaccess-dock-') as temp:
    create_test_station(rdk)
    rdk.setRunMode(rl.RUNMODE_SIMULATE)
    stoppable=rdk.AddProgram('VA disable regression')
    stoppable.setRunType(rl.PROGRAM_RUN_ON_SIMULATOR)
    stoppable.Pause(30000)
    configuration = Path(temp)/'configuration.json'
    report = Path(temp)/'report.json'
    configuration.write_text(json.dumps({'--python':sys.executable,'--bridge':str(ROOT/'VoiceAccess/_voiceaccess/bridge.py'),'--port':str(rdk.PORT)}))
    environment = os.environ.copy();environment.pop('ROBODK_AI',None)
    host = subprocess.run([str(ROOT/'build/dock-host/voiceaccess-dock-host'),str(ROOT/'VoiceAccess/_dock'/DOCK_LIBRARY),str(configuration),str(report)],capture_output=True,text=True,timeout=35,env=environment)
    print(host.stderr)
    assert host.returncode == 0,host.returncode
    data=json.loads(report.read_text())
    (ROOT/'build/reports/verificacio-dock-host.json').write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps(data,indent=2,ensure_ascii=False))
    assert data['native_view_in_host_window'] and data['embedded']
    assert data['rows'] > 2
    for key in ['outline_public_and_attribute_rows_match','outline_ax_selection_updates_model_checked','global_item_navigation_shortcuts_checked','focus_tree_shortcut_checked','expand_collapse_shortcuts_checked','non_root_fold_preserves_focus_and_navigation','context_simulation_available_for_program_only']:
        assert data[key],key
    assert data['host_menu_preserved'] and data['embedded_shortcut_routing_checked']
    assert data['host_can_shrink_to_500px']

    # Repeat with RoboDK's actual main window and plugin loader, still using
    # the disposable station, before ever loading into the user's session.
    rdk.setWindowState(rl.WINDOWSTATE_NORMAL)
    assert rdk.PluginLoad(str(ROOT/'VoiceAccess/_dock'/DOCK_LIBRARY))
    configured=json.loads(rdk.PluginCommand('VoiceAccess Dock','configure',configuration.read_text()))
    assert configured.get('configured'),configured
    for _ in range(60):
        actual=json.loads(rdk.PluginCommand('VoiceAccess Dock','report','{}'))
        if actual.get('rows',0)>2:break
        time.sleep(.1)
    assert actual.get('native_view_in_host_window') and actual.get('rows',0)>2,actual
    sizes=[]
    for width in [320,480,400]:
        rdk.PluginCommand('VoiceAccess Dock','resize',json.dumps({'width':width}))
        for _ in range(30):
            state=json.loads(rdk.PluginCommand('VoiceAccess Dock','status'))
            if abs(state['width']-width)<30:break
            time.sleep(.05)
        assert state['dock_area']==2 and state['minimum_width']<=320,state
        assert state['minimum_height']<=260,state
        assert abs(state['width']-width)<30,state
        sizes.append(state['width'])
    actual=json.loads(rdk.PluginCommand('VoiceAccess Dock','self-test',json.dumps({'preview':str(ROOT/'build/reports/evidence/voiceaccess-dock.png')})))
    assert actual['pid']==int(rdk.Command('MainProcess_ID'))
    assert actual['host_menu_preserved'] and actual['embedded_shortcut_routing_checked']
    assert actual['non_root_fold_preserves_focus_and_navigation']
    # Start from RoboDK's API (outside VoiceAccess), then disable VA mid-run.
    stoppable.RunCode()
    for _ in range(30):
        if stoppable.Busy():break
        time.sleep(.05)
    assert stoppable.Busy()
    before_hide=json.loads(rdk.PluginCommand('VoiceAccess Dock','report','{}'))
    rdk.PluginCommand('VoiceAccess Dock','hide','{}')
    rdk.setSelection([stoppable])
    for _ in range(50):
        if not stoppable.Busy():break
        time.sleep(.05)
    assert not stoppable.Busy(),'Disabling VA did not stop the external simulation'
    time.sleep(.8)
    disabled=json.loads(rdk.PluginCommand('VoiceAccess Dock','report','{}'))
    assert not disabled['reader_active'] and not disabled['background_polling_enabled']
    assert not disabled['own_speech_active'] and not disabled['speech_queue_pending']
    assert disabled['selected_name']==before_hide['selected_name'],'Hidden VA followed a new selection'
    rdk.PluginCommand('VoiceAccess Dock','show',json.dumps({'items':[str(stoppable.item)]}))
    time.sleep(.4)
    enabled=json.loads(rdk.PluginCommand('VoiceAccess Dock','report','{}'))
    assert enabled['reader_active'] and not stoppable.Busy()
    assert enabled['selected_name']=='VA disable regression'
    actual['disable_stops_external_simulation_and_speech_checked']=True
    actual['hidden_selection_following_suspended_checked']=True
    actual['reenable_does_not_restart_simulation_checked']=True
    actual['sidebar_widths_checked']=sizes
    (ROOT/'build/reports/verificacio-dock-robodk-aillat.json').write_text(json.dumps(actual,indent=2,ensure_ascii=False)+'\n')
    assert rdk.PluginLoad('VoiceAccess Dock',load=0)
    rdk.setWindowState(rl.WINDOWSTATE_HIDDEN)
    print('REAL_ROBODK_DOCK_CHECKS_PASSED')
