#!/usr/bin/env python3
"""Check shipped branding files, catalog mappings, dimensions and content hashes."""
from pathlib import Path
import hashlib,json,struct

ROOT=Path(__file__).resolve().parents[1]
manifest=json.loads((ROOT/'assets/branding/manifest.json').read_text())
for record in manifest['assets']:
    path=ROOT/record['path'];data=path.read_bytes()
    assert hashlib.sha256(data).hexdigest()==record['sha256'],f'Changed branding export: {path}'
    if path.suffix=='.png':
        assert data[:8]==b'\x89PNG\r\n\x1a\n',path
        assert list(struct.unpack('>II',data[16:24]))==record['size'],path

catalog=ROOT/'SPEXT/Assets.xcassets'
for name in ['AppIcon.appiconset','MenuBarIcon.imageset','SPEXTWordmark.imageset']:
    folder=catalog/name;contents=json.loads((folder/'Contents.json').read_text())
    for entry in contents['images']:
        path=folder/entry['filename'];assert path.is_file(),path
        if name=='AppIcon.appiconset':
            size=int(entry['size'].split('x')[0])*int(entry['scale'][0])
            assert struct.unpack('>II',path.read_bytes()[16:24])==(size,size),path
    if name=='MenuBarIcon.imageset':
        assert contents['properties']['template-rendering-intent']=='template'

assert (ROOT/'assets/branding/spext-app-icon.png').read_bytes()==(catalog/'AppIcon.appiconset/icon_512x512@2x.png').read_bytes()
print(f'Branding verified: {len(manifest["assets"])} hashes/dimensions, all icon slots and template catalog.')
