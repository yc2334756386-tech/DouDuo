#!/usr/bin/env python3
"""Generate the app's own glass/play icon without external packages."""
import json
import math
import pathlib
import struct
import sys
import zlib
import subprocess
import shutil

root = pathlib.Path(sys.argv[1]) / 'AppIcon.appiconset'
root.mkdir(parents=True, exist_ok=True)

def png(path, size):
    source=pathlib.Path(__file__).resolve().parents[1]/'Assets'/'IconOriginal.png'
    if source.is_file():
        if size==1024: shutil.copyfile(source,path)
        else: subprocess.run(['/usr/bin/sips','--resampleHeightWidth',str(size),str(size),str(source),'--out',str(path)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
        return
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            u, v = (x + .5) / size, (y + .5) / size
            glow = math.exp(-((u-.3)**2+(v-.25)**2)/.16)
            rgb = [int(8+17*glow+9*v), int(22+69*glow+11*v), int(29+82*glow+16*v)]
            # A luminous rounded-square pane with a second offset edge.
            qx, qy = abs(u-.5)-.23, abs(v-.5)-.23
            distance = math.hypot(max(qx,0),max(qy,0))+min(max(qx,qy),0)-.105
            if distance < 0:
                shade = .10 + .1*(1-v)
                rgb = [int(c*(1-shade)+230*shade) for c in rgb]
            edge = max(0,1-abs(distance)/.008)
            rgb = [min(255,int(c*(1-edge*.7)+target*edge*.7)) for c,target in zip(rgb,[186,245,248])]
            # Centered, slightly softened play mark.
            px, py = u-.445, v-.5
            triangle = px >= 0 and px < .19 and abs(py) < (.19-px)*.81
            if triangle: rgb = [220,251,249]
            rows.extend(rgb)
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows,8))+chunk(b'IEND',b''))

images=[]
for idiom, points, scales in [('iphone',20,[2,3]),('iphone',29,[2,3]),('iphone',40,[2,3]),('iphone',60,[2,3]),
                               ('ipad',20,[1,2]),('ipad',29,[1,2]),('ipad',40,[1,2]),('ipad',76,[1,2]),('ipad',83.5,[2]),('ios-marketing',1024,[1])]:
    for scale in scales:
        size=round(points*scale)
        filename=f'icon-{size}.png'
        if not (root/filename).exists(): png(root/filename,size)
        images.append({'idiom':idiom,'size':f'{points}x{points}','scale':f'{scale}x','filename':filename})
(root/'Contents.json').write_text(json.dumps({'images':images,'info':{'version':1,'author':'DouGlass'}},indent=2),encoding='utf-8')
(root.parent/'Contents.json').write_text('{"info":{"version":1,"author":"DouGlass"}}',encoding='utf-8')
