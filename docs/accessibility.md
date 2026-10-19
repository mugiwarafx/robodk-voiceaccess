# Accessibility testing

Automated accessibility attributes are useful evidence, but they do not establish
that a workflow is usable with a screen reader. Test the complete interaction
with VoiceOver as well as ordinary keyboard navigation.

## Manual checks

| Check | Expected behavior |
| --- | --- |
| Open VA from the menu, toolbar, or context menu | The sidebar opens inside RoboDK and focuses its accessible tree. |
| Navigate with ⌘↑ / ⌘↓ | Selection and the spoken item agree. |
| Expand and collapse with ⌘→ / ⌘← | Children appear or disappear; focus stays on the parent. |
| Search, then clear the query | Matching ancestors are available, and collapsed state is restored. |
| Read selection | Only item names are read. |
| Read details | Context, coordinates, visibility, and program information are available on demand. |
| Use VoiceOver with local speech enabled in preferences | The local speech process stays silent; VoiceOver remains the single output. |
| Tab through controls and open the item context menu | Controls have useful names and can be reached and activated. |
| Resize and move the sidebar | Controls remain usable; shorter panels scroll. |
| Follow a simulation | Main-program step counts and movement announcements remain understandable. Fast steps may be omitted. |
| Disable VA using the icon or dock close button | Playback in the simulator stops, pending local speech is cleared, and automatic item reading stops. |
| Change RoboDK selection while VA is disabled | VA stays silent and does not follow the new selection. |
| Enable VA again | Reading returns, but playback does not restart. |

VO is the VoiceOver modifier, normally Control + Option. Record Quick Nav state,
interaction mode, the exact key sequence, and which control had focus when
reporting a problem. Keyboard focus and the VoiceOver cursor can differ.

## Current boundaries

The helper exposes station data and simulation state through its own controls.
RoboDK's original menus, dialogs, toolbar, station tree, and 3D view continue to
use their existing accessibility behavior. VoiceAccess does not claim full
screen-reader coverage of the application.

The macOS implementation has received iterative user testing. The dock and
screen-reader combination still needs broader validation across OS versions,
RoboDK builds, hardware, and VoiceOver settings. NVDA and Orca are planned and
must not be reported as supported platforms today.
