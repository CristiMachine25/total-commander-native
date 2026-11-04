#!/usr/bin/env python3
"""Index documented INI declarations; this is discovery, not parity certification."""
import csv, hashlib, json, re, sys
from html.parser import HTMLParser
from pathlib import Path
class Declarations(HTMLParser):
    def __init__(self):
        super().__init__(); self.depth=0;self.text='';self.items=[]
    def handle_starttag(self,tag,attrs):
        if tag=='span' and dict(attrs).get('class')=='s18':self.depth=1;self.text=''
        elif self.depth:self.depth+=1
    def handle_endtag(self,tag):
        if self.depth:
            self.depth-=1
            if not self.depth:self.items.append(self.text.strip())
    def handle_data(self,text):
        if self.depth:self.text+=text
root=Path(sys.argv[1]);dest=Path(sys.argv[2]);dest.mkdir(parents=True,exist_ok=True)
rows=[];inputs=[]
for name in ['inisettings.htm','inisettings1.htm','inisettings2.htm','inisettings3.htm','wcx_ftp_ini_settings.htm']:
    path=root/name;raw=path.read_bytes();parser=Declarations();parser.feed(raw.decode('cp1252'))
    section='Configuration' if name in ['inisettings1.htm','inisettings2.htm'] else 'unspecified'
    count=0
    for ordinal,item in enumerate(parser.items,1):
        match=re.match(r'^\[([^\]]+)\]',item)
        if match:section=match.group(1);continue
        if '=' not in item:continue
        key,value=item.split('=',1);key=key.strip()
        if not key or len(key)>100 or not re.match(r'^[A-Za-z0-9_.*?<> /+()\[\]-]+$',key):continue
        rows.append(dict(source=name,section=section,key=key,documented_value=value.strip(),source_span=ordinal,status='unverified',note='Documented declaration; not a claim of native support. Cross-reference the option-level dialog audits.'));count+=1
    inputs.append(dict(source=name,sha256=hashlib.sha256(raw).hexdigest(),declarations=count))
with (dest/'original-ini-inventory.csv').open('w',newline='') as f:
    writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
(dest/'original-ini-inventory.json').write_text(json.dumps(dict(inputs=inputs,rows=len(rows),scope='Literal declarations in s18 spans of five original help pages. Numbered templates and examples may overlap; counts are not unique settings or implementation coverage. Other markup, undocumented settings, dynamic plugin options and behavior require separate investigation.'),indent=2)+'\n')
print(f'Indexed {len(rows)} documented INI declarations; every row explicitly unverified.')
