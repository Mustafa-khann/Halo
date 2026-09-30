import sys
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias

mount = Path(sys.argv[1])
alias = Alias.for_file(str(mount / '.background' / 'background.png')).to_bytes()
window = {
    'ContainerShowSidebar': False, 'ShowPathbar': False, 'ShowSidebar': False,
    'ShowStatusBar': False, 'ShowTabView': False, 'ShowToolbar': False,
    'WindowBounds': '{{280, 180}, {600, 400}}',
}
icons = {
    'viewOptionsVersion': 1, 'backgroundType': 2, 'backgroundImageAlias': alias,
    'iconSize': 96.0, 'textSize': 12.0, 'gridSpacing': 100.0,
    'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'arrangeBy': 'none',
    'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    'showIconPreview': True, 'showItemInfo': False, 'labelOnBottom': True,
}
with DSStore.open(str(mount / '.DS_Store'), 'w+') as store:
    # ds_store encodes these known records as binary plists itself.
    store['.']['bwsp'] = window
    store['.']['icvp'] = icons
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['Halo.app']['Iloc'] = (180, 190)
    store['Applications']['Iloc'] = (420, 190)

with DSStore.open(str(mount / '.DS_Store'), 'r') as store:
    assert store['.']['bwsp'] == window
    assert store['.']['icvp'] == icons
    assert store['Halo.app']['Iloc'] == (180, 190)
    assert store['Applications']['Iloc'] == (420, 190)
