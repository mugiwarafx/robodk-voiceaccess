"""Check action routing without launching or changing the user's RoboDK."""
from pathlib import Path
import json
import sys
import tempfile
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'VoiceAccess'))
from _voiceaccess import integration

with tempfile.TemporaryDirectory() as directory:
    addin=Path(directory)
    (addin/'_dock').mkdir()
    (addin/'_dock'/integration.DOCK_LIBRARY).touch()
    (addin/'_dock/ENABLED').touch()
    (addin/'_native/VoiceAccess.app/Contents/MacOS').mkdir(parents=True)
    (addin/'_native/VoiceAccess.app/Contents/MacOS/VoiceAccess').touch()
    rdk=MagicMock();rdk.PORT=20500;item=MagicMock();item.item=123;rdk.Selection.return_value=[item]
    calls=[]
    def plugin(name,command,value=''):
        calls.append((command,value))
        if command=='status':return json.dumps({'available':True,'embedded':False})
        if command=='configure':return '{"configured":true}'
        return '{"embedded":true}'
    rdk.PluginCommand.side_effect=plugin
    with patch.object(integration,'ADDIN',addin),patch.object(integration.subprocess,'run') as run:
        assert integration.invoke(rdk,'show')['embedded']
        run.assert_not_called()
        assert [c[0] for c in calls]==['status','configure','show']
        assert json.loads(calls[-1][1])['items']==['123']
        calls.clear()
        integration.invoke(rdk,'hide')
        assert [c[0] for c in calls]==['status']
        # No compatible native plugin: preserve the existing singleton IPC path.
        rdk.PluginCommand.side_effect=None;rdk.PluginCommand.return_value='ERROR'
        rdk.PluginLoad.return_value=False;run.return_value.returncode=0
        assert integration.invoke(rdk,'show')['reused_panel']
        assert '--request' in run.call_args.args[0]
print('Native dock routing, captured selection, hidden dock no-op and companion fallback: passed')
