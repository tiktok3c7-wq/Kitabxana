#!/bin/bash
# Build zamanı işləyir: 1) pdf.js-i APK-nın içinə qoyur  2) panoya kopyalama  3) PDF seçimini Android özü edir
set -e
A=_apk/app/src/main/assets
curl -fL --retry 3 -o $A/pdf.min.js https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js
curl -fL --retry 3 -o $A/pdf.worker.min.js https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js
test $(stat -c%s $A/pdf.min.js) -gt 100000
test $(stat -c%s $A/pdf.worker.min.js) -gt 100000
python3 - <<'PY'
J='_apk/app/src/main/java/com/kitabxanam/app/MainActivity.java'
s=open(J,encoding='utf-8').read()

# --- 1) Bridge: copyText + pickedDone, və PDF kopyalama metodları ---
m='''void handlePicked(int res, Intent data) {
        final java.util.ArrayList<Uri> copy = new java.util.ArrayList<Uri>();
        final java.util.ArrayList<Uri> direct = new java.util.ArrayList<Uri>();
        if (res == RESULT_OK && data != null) {
            java.util.ArrayList<Uri> all = new java.util.ArrayList<Uri>();
            if (data.getClipData() != null) {
                for (int i = 0; i < data.getClipData().getItemCount(); i++) all.add(data.getClipData().getItemAt(i).getUri());
            } else if (data.getData() != null) {
                all.add(data.getData());
            }
            for (Uri u : all) {
                String t = null;
                try { t = getContentResolver().getType(u); } catch (Exception e) { }
                if (t != null && (t.startsWith("image/") || t.startsWith("video/"))) direct.add(u); else copy.add(u);
            }
        }
        if (direct.isEmpty()) chooser.onReceiveValue(null);
        else chooser.onReceiveValue(direct.toArray(new Uri[0]));
        if (copy.isEmpty()) return;
        toast("Fayl hazırlanır: " + copy.size());
        new Thread(new Runnable() { public void run() { copyPicked(copy); } }).start();
    }

    void copyPicked(java.util.ArrayList<Uri> list) {
        File dir = new File(getCacheDir(), "picked");
        dir.mkdirs();
        File[] old = dir.listFiles();
        if (old != null) for (File f : old) f.delete();
        final org.json.JSONArray arr = new org.json.JSONArray();
        for (int i = 0; i < list.size(); i++) {
            Uri u = list.get(i);
            String name = "fayl" + i;
            String type = "";
            try {
                android.database.Cursor c = getContentResolver().query(u, null, null, null, null);
                if (c != null) {
                    try {
                        int ix = c.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME);
                        if (c.moveToFirst() && ix >= 0) {
                            String dn = c.getString(ix);
                            if (dn != null && dn.length() > 0) name = dn;
                        }
                    } finally { c.close(); }
                }
                String t = getContentResolver().getType(u);
                if (t != null) type = t;
            } catch (Exception e) { }
            org.json.JSONObject o = new org.json.JSONObject();
            try {
                o.put("name", name);
                o.put("type", type);
                String safe = i + "_" + name.replaceAll("[^A-Za-z0-9._-]", "_");
                File out = new File(dir, safe);
                InputStream in = getContentResolver().openInputStream(u);
                if (in == null) throw new IOException("açıla bilmədi");
                FileOutputStream os = new FileOutputStream(out);
                byte[] buf = new byte[65536];
                int rd;
                while ((rd = in.read(buf)) > 0) os.write(buf, 0, rd);
                os.close();
                in.close();
                o.put("file", safe);
            } catch (Throwable ex) {
                try { o.put("error", String.valueOf(ex.getMessage() != null ? ex.getMessage() : ex.toString())); } catch (Exception x2) { }
            }
            arr.put(o);
        }
        final String js = "window.__picked&&window.__picked(" + arr.toString() + ")";
        runOnUiThread(new Runnable() { public void run() { web.evaluateJavascript(js, null); } });
    }

    class Bridge {
                @JavascriptInterface
                public void pickedDone() {
                    File[] fs = new File(getCacheDir(), "picked").listFiles();
                    if (fs != null) for (File f : fs) f.delete();
                }

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

# --- 2) fayl seçici: filtrsiz, sistem seçicisi ---
old='startActivityForResult(p.createIntent(), REQ_FILE);'
new='''Intent it = new Intent(Intent.ACTION_GET_CONTENT);
                              it.addCategory(Intent.CATEGORY_OPENABLE);
                              it.setType("*/*");
                              it.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                              startActivityForResult(it, REQ_FILE);'''
assert old in s
s=s.replace(old,new,1)

# --- 3) nəticəni özümüz emal edək ---
old2='chooser.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(res, data));'
assert old2 in s
s=s.replace(old2,'handlePicked(res, data);',1)

# --- 4) kopyalanmış PDF-ləri səhifəyə veririk ---
old3='if (p == null || p.isEmpty() || p.equals("/")) p = "/index.html";'
assert old3 in s
blk='''if (p != null && p.startsWith("/__picked/")) {
                              try {
                                  File pf = new File(new File(getCacheDir(), "picked"), p.substring(10));
                                  return new WebResourceResponse("application/octet-stream", null, new java.io.FileInputStream(pf));
                              } catch (Exception e) {
                                  return new WebResourceResponse("text/plain", "UTF-8", 404, "Not Found", null, new ByteArrayInputStream(new byte[0]));
                              }
                          }
                          '''
s=s.replace(old3,blk+old3,1)
open(J,'w',encoding='utf-8').write(s)

I='_apk/app/src/main/assets/inject.js'
t=open(I,encoding='utf-8').read()
t+="\n(function(){var w=function(x){Android.copyText(String(x));return Promise.resolve();};try{navigator.clipboard.writeText=w;}catch(e){}try{Object.defineProperty(navigator.clipboard,'writeText',{value:w,configurable:true});}catch(e){}})();\n"
open(I,'w',encoding='utf-8').write(t)
PY
