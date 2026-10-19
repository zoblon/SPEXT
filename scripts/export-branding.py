#!/usr/bin/env python3
"""Export app assets and social preview from the approved V10 masters (Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, hashlib, os

ROOT=Path(__file__).resolve().parents[1]
BRAND=ROOT/'assets/branding'
CATALOG=ROOT/'SPEXT/Assets.xcassets'
app=Image.open(BRAND/'spext-app-icon.png').convert('RGBA')
catalog=json.loads((CATALOG/'AppIcon.appiconset/Contents.json').read_text())
for entry in catalog['images']:
    size=round(float(entry['size'].split('x')[0])*int(entry['scale'][0]))
    target=CATALOG/'AppIcon.appiconset'/entry['filename']
    if app.size==(size,size):
        target.write_bytes((BRAND/'spext-app-icon.png').read_bytes())
    else:
        app.resize((size,size),Image.Resampling.LANCZOS).save(target)

def imageset(name,filenames,template=False):
    folder=CATALOG/(name+'.imageset');folder.mkdir(exist_ok=True)
    data={'images':[],'info':{'author':'xcode','version':1}}
    for scale,filename in enumerate(filenames,1):
        source=BRAND/filename
        (folder/filename).write_bytes(source.read_bytes())
        data['images'].append({'filename':filename,'idiom':'universal','scale':f'{scale}x'})
    if template:data['properties']={'template-rendering-intent':'template'}
    (folder/'Contents.json').write_text(json.dumps(data,indent=2)+'\n')

menu=Image.open(BRAND/'sources/spext-menubar.png').convert('RGBA')
menu=menu.crop(menu.getchannel('A').getbbox())
menu_names=[]
for scale in (1,2,3):
    fit=menu.copy();fit.thumbnail((16*scale,16*scale),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(18*scale,18*scale))
    canvas.alpha_composite(fit,((canvas.width-fit.width)//2,(canvas.height-fit.height)//2))
    filename='spext-menubar'+('' if scale==1 else f'@{scale}x')+'.png'
    canvas.save(BRAND/filename);menu_names.append(filename)
imageset('MenuBarIcon',menu_names,True)

logo=Image.open(BRAND/'spext-logo.png').convert('RGBA')
names=[]
for scale in (1,2,3):
    name='spext-wordmark'+('' if scale==1 else f'@{scale}x')+'.png'
    logo.resize((120*scale,round(120*scale*logo.height/logo.width)),Image.Resampling.LANCZOS).save(BRAND/name)
    names.append(name)
imageset('SPEXTWordmark',names)

# Supporting text is separate from the unchanged approved wordmark.
regular=os.environ.get('SPEXT_FONT_REGULAR','/System/Library/Fonts/Supplemental/Arial.ttf')
bold=os.environ.get('SPEXT_FONT_BOLD','/System/Library/Fonts/Supplemental/Arial Bold.ttf')
scale=2
social=Image.new('RGB',(1280*scale,640*scale),'#F5F3FF');draw=ImageDraw.Draw(social)
def text(x,y,copy,size,color,font=regular):
    face=ImageFont.truetype(font,size*scale)
    bounds=draw.textbbox((x*scale,y*scale),copy,font=face)
    assert bounds[2]<1216*scale and bounds[3]<608*scale,(copy,bounds)
    draw.text((x*scale,y*scale),copy,font=face,fill=color)
text(88,64,'macOS dictation app',23,'#6242DE',bold)
brand=logo.copy();brand.thumbnail((1104*scale,250*scale),Image.Resampling.LANCZOS)
social.paste(brand,(88*scale,146*scale),brand)
text(94,418,'Speech to text. Straight into your app.',37,'#34226D',bold)
text(96,484,'Hold a hotkey. Speak. Release.',27,'#6E6287')
text(96,570,'Independent project · github.com/zoblon/SPEXT',18,'#6E6287')
social.resize((1280,640),Image.Resampling.LANCZOS).save(BRAND/'spext-social-preview.png')
records=[]
for folder in (BRAND,CATALOG/'AppIcon.appiconset',CATALOG/'MenuBarIcon.imageset',CATALOG/'SPEXTWordmark.imageset'):
    for path in sorted(folder.iterdir()):
        if path.suffix in ('.png','.svg'):
            record={'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
            if path.suffix=='.png':record['size']=list(Image.open(path).size)
            records.append(record)
manifest={'approval':'Tobi accepted V10 and requested integration on 2026-10-19.','generation':'V6 generated lettering alpha; V7 bolt traced, V9 height/shear, V10 width scaling. Derived assets use native SVG placement and deterministic resizing.','palette':['#8B7CF4','#6242DE','#C9FF32'],'limitations':'Raster letter silhouettes embedded in SVG; not a full-vector typeface.','assets':records}
(BRAND/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(f'Exported and hashed {len(records)} production assets.')
