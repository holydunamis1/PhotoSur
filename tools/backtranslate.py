import json,sys,re,difflib,os
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM
import torch
lang=sys.argv[1]
M={'ar':'arb_Arab','bg':'bul_Cyrl','bn':'ben_Beng','ca':'cat_Latn','cs':'ces_Latn','da':'dan_Latn','de':'deu_Latn','el':'ell_Grek','es':'spa_Latn','fa':'pes_Arab','fi':'fin_Latn','fil':'tgl_Latn','fr':'fra_Latn','gu':'guj_Gujr','he':'heb_Hebr','hi':'hin_Deva','hu':'hun_Latn','id':'ind_Latn','it':'ita_Latn','ja':'jpn_Jpan','ko':'kor_Hang','ml':'mal_Mlym','mr':'mar_Deva','ms':'zsm_Latn','nb':'nob_Latn','nl':'nld_Latn','pl':'pol_Latn','pt':'por_Latn','ro':'ron_Latn','ru':'rus_Cyrl','sk':'slk_Latn','sv':'swe_Latn','sw':'swh_Latn','ta':'tam_Taml','te':'tel_Telu','th':'tha_Thai','tr':'tur_Latn','uk':'ukr_Cyrl','ur':'urd_Arab','vi':'vie_Latn','zh':'zho_Hans','zh_Hant':'zho_Hant'}
src=M[lang]
d='app/lib/l10n/'
en=json.load(open(d+'app_en.arb',encoding='utf-8'));tr=json.load(open(d+f'app_{lang}.arb',encoding='utf-8'))
keys=[k for k in en if not k.startswith('@') and en[k]!=tr.get(k) and len(en[k])>3]
name='facebook/nllb-200-distilled-600M'
tok=AutoTokenizer.from_pretrained(name,src_lang=src);m=AutoModelForSeq2SeqLM.from_pretrained(name).eval()
def prot(s):return re.sub(r'\{(\w+)\}',lambda x:'['+x.group(1)+']',s)
out=[]
for i in range(0,len(keys),16):
    b=keys[i:i+16]
    x=tok([prot(tr[k]) for k in b],return_tensors='pt',padding=True,truncation=True,max_length=256)
    with torch.no_grad():y=m.generate(**x,forced_bos_token_id=tok.convert_tokens_to_ids('eng_Latn'),max_new_tokens=256,num_beams=3)
    for k,t in zip(b,tok.batch_decode(y,skip_special_tokens=True)):
        a=re.sub(r'[^\w ]','',en[k].lower());c=re.sub(r'[^\w ]','',t.lower())
        sim=round(difflib.SequenceMatcher(None,a.split(),c.split()).ratio(),2)
        out.append({'k':k,'en':en[k],'tr':tr[k],'back':t,'sim':sim})
os.makedirs('out',exist_ok=True)
json.dump(out,open(f'out/{lang}.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
