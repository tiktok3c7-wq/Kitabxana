#!/bin/bash
# Build zamanı işləyir: pdf.js-i APK-nın içinə qoyur (internetsiz PDF) və panoya kopyalama əlavə edir
set -e
A=_apk/app/src/main/assets
curl -fL --retry 3 -o $A/pdf.min.js https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js
curl -fL --retry 3 -o $A/pdf.worker.min.js https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js
test $(stat -c%s $A/pdf.min.js) -gt 100000
test $(stat -c%s $A/pdf.worker.min.js) -gt 100000
python3 - <<'PY'
J='_apk/app/src/main/java/com/kitabxanam/app/MainActivity.java'
s=open(J,encoding='utf-8').read()
m='''class Bridge {
                @JavascriptInterface
                public void copyText(final String t) {
                    runOnUiThread(new Runnable() {
                        public void run() {
                            ClipboardManager cm = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
                            cm.setPrimaryClip(ClipData.newPlainText("text", t));
                            Toast.makeText(MainActivity.this, "Kopyalandı ✓", Toast.LENGTH_SHORT).show();
                        }
                    });
                }
'''
assert 'class Bridge {' in s
s=s.replace('class Bridge {',m,1)
open(J,'w',encoding='utf-8').write(s)
old='startActivityForResult(p.createIntent(), REQ_FILE);'
new='''Intent it = new Intent(Intent.ACTION_GET_CONTENT);
                              it.addCategory(Intent.CATEGORY_OPENABLE);
                              it.setType("*/*");
                              it.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                              startActivityForResult(it, REQ_FILE);'''
s=open(J,encoding='utf-8').read()
assert old in s
s=s.replace(old,new,1)
open(J,'w',encoding='utf-8').write(s)
I='_apk/app/src/main/assets/inject.js'
t=open(I,encoding='utf-8').read()
t+="\n(function(){var w=function(x){Android.copyText(String(x));return Promise.resolve();};try{navigator.clipboard.writeText=w;}catch(e){}try{Object.defineProperty(navigator.clipboard,'writeText',{value:w,configurable:true});}catch(e){}})();\n"
open(I,'w',encoding='utf-8').write(t)
PY
