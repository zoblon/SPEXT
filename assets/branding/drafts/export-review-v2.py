from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json, shutil

out=Path(__file__).resolve().parent
def bounds(im): return im.getchannel('A').point(lambda a:255 if a>=16 else 0).getbbox()
logo=Image.open(out/'spext-logo-source-v2.png').convert('RGBA')
box=bounds(logo); cropped=logo.crop(box)
master=Image.new('RGBA',(cropped.width+96,cropped.height+96),(0,0,0,0))
master.alpha_composite(cropped,(48,48)); master.save(out/'spext-logo-v2.png',optimize=True)
app=Image.open(out/'spext-app-icon-source-v1.png').convert('RGBA')
app.resize((1024,1024),Image.Resampling.LANCZOS).save(out/'spext-app-icon-v1.png',optimize=True)
menu=Image.open(out/'spext-menubar-source-v1.png').convert('RGBA'); menu=menu.crop(bounds(menu))
for density in (1,2,3):
 canvas=Image.new('RGBA',(18*density,18*density),(0,0,0,0)); fit=menu.copy()
 fit.thumbnail((16*density,16*density),Image.Resampling.LANCZOS)
 canvas.alpha_composite(fit,((canvas.width-fit.width)//2,(canvas.height-fit.height)//2))
 canvas.save(out/('spext-menubar-v1'+('' if density==1 else '@'+str(density)+'x')+'.png'),optimize=True)

# Exact-copy composition using the generated logo, no redrawn brand elements.
s=2; preview=Image.new('RGB',(1280*s,640*s),'#F5F1FF'); d=ImageDraw.Draw(preview)
regular='/System/Library/Fonts/Supplemental/Arial.ttf'
bold='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def text(x,y,copy,size,color,font=regular):
 f=ImageFont.truetype(font,size*s); b=d.textbbox((x*s,y*s),copy,font=f)
 assert b[0]>=0 and b[2]<1216*s and b[3]<608*s,(copy,b)
 d.text((x*s,y*s),copy,fill=color,font=f)
d.rounded_rectangle((88*s,64*s,345*s,108*s),radius=22*s,fill='#CBFF37')
text(108,74,'macOS dictation app',22,'#382063',bold)
brand=cropped.resize((1104*s,round(cropped.height/cropped.width*1104)*s),Image.Resampling.LANCZOS)
preview.paste(brand,(88*s,169*s),brand)
text(94,408,'Speech to text. Straight into your app.',37,'#382063',bold)
text(96,473,'Hold a hotkey. Speak. Release.',27,'#776393')
text(96,568,'Independent project · github.com/zoblon/SPEXT',18,'#776393')
preview.resize((1280,640),Image.Resampling.LANCZOS).save(out/'spext-social-preview-v2.png',optimize=True)

# Actual export review, including template rendering on light/dark UI.
sheet=Image.new('RGB',(1280,1120),'#F5F1FF'); q=ImageDraw.Draw(sheet)
f=ImageFont.truetype(bold,21); small=ImageFont.truetype(regular,17)
q.text((56,34),'SPEXT · Entwurf 2 · Freigabe offen',font=f,fill='#382063')
show=master.copy(); show.thumbnail((1150,245),Image.Resampling.LANCZOS); sheet.paste(show,((1280-show.width)//2,78),show)
q.line((56,350,1224,350),fill='#DDD3EE',width=1)
q.text((64,380),'App-Icon',font=f,fill='#382063'); tile=app.resize((245,245),Image.Resampling.LANCZOS); sheet.paste(tile,(48,418),tile)
q.text((355,380),'Menüleiste · tatsächliche Größe',font=f,fill='#382063')
for i,bg in enumerate(['#FFFFFF','#2A2530']):
 y=438+i*98;q.rounded_rectangle((355,y,765,y+70),radius=12,fill=bg)
 for j,size in enumerate([18,36]):
  alpha=Image.open(out/('spext-menubar-v1'+('' if j==0 else '@2x')+'.png')).getchannel('A')
  glyph=Image.new('RGBA',alpha.size,'#29242F' if i==0 else '#FFFFFF');glyph.putalpha(alpha)
  sheet.paste(glyph,(385+j*100,y+(70-size)//2),glyph)
q.text((355,638),'18 px / 2× · hell und dunkel',font=small,fill='#776393')
q.text((850,380),'Farben',font=f,fill='#382063')
for i,color in enumerate(['#682DE5','#A276FF','#C9FF32']):
 q.rounded_rectangle((850+i*112,425,938+i*112,513),radius=16,fill=color)
 q.text((850+i*112,532),color,font=small,fill='#776393')
q.text((64,711),'GitHub Social Preview · Englisch',font=f,fill='#382063')
social=Image.open(out/'spext-social-preview-v2.png');social.thumbnail((650,325),Image.Resampling.LANCZOS);sheet.paste(social,(60,754))
sheet.save(out/'spext-review-v2.png',optimize=True)
records=[]
for path in sorted(out.glob('*.png')):
 im=Image.open(path); records.append({'file':path.name,'dimensions':list(im.size),'mode':im.mode,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(out/'asset-manifest-v2.json').write_text(json.dumps({'status':'Drafts; awaiting Tobi approval. Not integrated or published.','generation':'Built-in Codex imagegen; deterministic resizing and exact-copy layout.','typography':'Generated bespoke wordmark artwork, not an installable font. Supporting text: Arial.','palette_intent':['#682DE5','#A276FF','#C9FF32'],'social_copy':['macOS dictation app','Speech to text. Straight into your app.','Hold a hotkey. Speak. Release.','Independent project · github.com/zoblon/SPEXT'],'assets':records},indent=2)+'\n')
print(json.dumps(records,indent=2))
