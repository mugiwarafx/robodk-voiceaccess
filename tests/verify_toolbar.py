from pathlib import Path
import tempfile,sys,json,os
from unittest.mock import patch,MagicMock
sys.path.insert(0,str(Path(__file__).resolve().parents[1] / 'VoiceAccess'))
from _voiceaccess import toolbar
import OpenVoiceAccess as action
with tempfile.TemporaryDirectory() as directory:
 path=Path(directory)/'state.json'
 with patch.object(toolbar,'state_path',return_value=path):
  assert not toolbar.panel_visible(20500)
  rdk=MagicMock();rdk.PORT=20500
  calls=[]
  def plugin(name,command,value=None):
   calls.append((command,value))
   if command=='AddinListJson':return json.dumps([{'identifier':'com.robodk.voiceaccess','path':'own','status':2}])
   assert toolbar.panel_visible(20500)==(json.loads(value)['operation']=='check')
   return '{"error":0}'
  rdk.PluginCommand.side_effect=plugin
  for visible in [True,False]:
   assert toolbar.sync_toolbar(rdk,visible,os.getpid())['toolbar_updated']
   assert toolbar.panel_visible(20500)==visible
  path.write_text('{"pid":2147483647,"visible":true}')
  assert not toolbar.panel_visible(20500)
 for checked,unchecked,visible,expected in [(True,False,False,'show'),(True,False,True,None),(False,True,True,'hide'),(False,True,False,None),(False,False,False,'show')]:
  with patch.object(action.robolink,'Robolink') as link,patch.object(action.roboapps,'Checked',return_value=checked),patch.object(action.roboapps,'Unchecked',return_value=unchecked),patch.object(action.roboapps,'KeepChecked'),patch.object(action,'panel_visible',return_value=visible),patch.object(action,'invoke') as invoke:
   action.runmain()
   if expected:assert invoke.call_args.args[1]==expected
   else:invoke.assert_not_called()
print('Toolbar synchronization, feedback suppression, show/hide toggles, stale owner: passed')
