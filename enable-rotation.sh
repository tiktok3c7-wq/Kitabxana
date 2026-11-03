#!/usr/bin/env bash
# Kitabxanam: APK-da ekranın dönməsini (Dikey / Avto-döndür) aktiv edir.
# İstifadə:  bash enable-rotation.sh [layihə_qovluğu]      (qovluq verilməsə cari qovluq)
# patch.sh-ın SONUNA (Gradle build-dən əvvəl) əlavə et:   bash enable-rotation.sh "$PWD"
# Nə edir:
#  1) AndroidManifest.xml-də əsas (MAIN/LAUNCHER) activity-dən screenOrientation kilidini götürür -> "unspecified" (telefonun ayarına tabe olur)
#  2) configChanges əlavə edir ki, dönəndə proqram yenidən başlamasın və açıq fayl itməsin
#  3) Java/Kotlin kodunda SCREEN_ORIENTATION_PORTRAIT kilidi varsa onu da açır
# Skript təkrar işlədilsə zərər vermir.
set -e
ROOT="${1:-.}"
MANIFESTS=$(find "$ROOT" -name AndroidManifest.xml -path '*src/main*' -not -path '*/build/*' -not -path '*/node_modules/*' 2>/dev/null || true)
[ -z "$MANIFESTS" ] && { echo "AndroidManifest.xml tapılmadı: $ROOT"; exit 1; }
for M in $MANIFESTS; do
python3 - "$M" <<'PY'
import re,sys
p=sys.argv[1];s=open(p,encoding='utf-8').read()
FLAGS=['orientation','screenSize','screenLayout','smallestScreenSize','keyboardHidden','keyboard','uiMode']
changed=False
def patch_activity(m):
    global changed
    full=m.group(0)
    if 'android.intent.action.MAIN' not in full: return full
    tag_end=full.index('>')
    # self-closing olmayan activity: başlıq teqi full[:tag_end+1]
    head,rest=full[:tag_end+1],full[tag_end+1:]
    new=head
    if re.search(r'android:screenOrientation\s*=',new):
        new2=re.sub(r'android:screenOrientation\s*=\s*"[^"]*"','android:screenOrientation="unspecified"',new)
    else:
        new2=re.sub(r'(<activity\b)',r'\1 android:screenOrientation="unspecified"',new,1)
    new=new2
    mcc=re.search(r'android:configChanges\s*=\s*"([^"]*)"',new)
    if mcc:
        cur=[x for x in mcc.group(1).split('|') if x]
        for f in FLAGS:
            if f not in cur: cur.append(f)
        new=new.replace(mcc.group(0),'android:configChanges="'+'|'.join(cur)+'"')
    else:
        new=re.sub(r'(<activity\b)',r'\1 android:configChanges="'+'|'.join(FLAGS)+'"',new,1)
    if new!=head: changed=True
    return new+rest
out=re.sub(r'<activity\b[^>]*>.*?</activity>',patch_activity,s,flags=re.S)
if out!=s:
    open(p,'w',encoding='utf-8').write(out);print('Manifest yeniləndi:',p)
else: print('Manifest artıq hazırdır:',p)
PY
done
# Kodda kilid varsa aç
SRC=$(grep -rl "SCREEN_ORIENTATION_PORTRAIT\|SCREEN_ORIENTATION_SENSOR_PORTRAIT\|SCREEN_ORIENTATION_USER_PORTRAIT" "$ROOT" --include=*.java --include=*.kt 2>/dev/null | grep -v '/build/' || true)
for F in $SRC; do
  sed -i 's/SCREEN_ORIENTATION_PORTRAIT/SCREEN_ORIENTATION_UNSPECIFIED/g;s/SCREEN_ORIENTATION_SENSOR_PORTRAIT/SCREEN_ORIENTATION_UNSPECIFIED/g;s/SCREEN_ORIENTATION_USER_PORTRAIT/SCREEN_ORIENTATION_UNSPECIFIED/g' "$F"
  echo "Kod kilidi açıldı: $F"
done
echo "Hazırdır: ekran dönməsi aktivdir."
