#!/usr/bin/env python3
"""Local stand-in for the Internet Archive and Jamendo APIs, to test the
"Música livre" page offline:

    python3 tools/mock_freemusic.py 8099 <some.mp3>
    ARARA_IA_BASE=http://127.0.0.1:8099 ARARA_JAMENDO_BASE=http://127.0.0.1:8099/v3.0 arara-music
"""
import json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
AUDIO = open(sys.argv[2], "rb").read() if len(sys.argv) > 2 else b"ID3" + b"\0" * 4000
BASE = f"http://127.0.0.1:{PORT}"
CC = "https://creativecommons.org/licenses/by-sa/4.0/"

ITEMS = {
    "forro-livre-2019": {"title": "Forró Livre", "creator": "Trio Mandacaru", "lic": CC,
        "files": [("01 Asa Branca no Pé.mp3", "Asa Branca no Pé", "3:12"), ("02 Sanfona de Domingo.mp3", "Sanfona de Domingo", "2:48"), ("03 Xote da Lua.mp3", "Xote da Lua", "4:05")]},
    "chorinho-domínio": {"title": "Choros de 1920", "creator": "Regional do Bairro", "lic": "http://creativecommons.org/publicdomain/mark/1.0/",
        "files": [("Carinhoso (1928).mp3", "Carinhoso", "3:01")]},
    "sem-licenca": {"title": "Não deve aparecer", "creator": "X", "lic": "", "files": [("x.mp3", "x", "1:00")]},
}

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)): body = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        u = urllib.parse.urlparse(self.path); q = urllib.parse.parse_qs(u.query); path = urllib.parse.unquote(u.path)
        if path == "/advancedsearch.php":
            docs = [{"identifier": k, "title": v["title"], "creator": v["creator"]} for k, v in ITEMS.items()]
            return self.send(200, {"response": {"numFound": len(docs), "docs": docs}})
        if path.startswith("/metadata/"):
            it = ITEMS.get(path.split("/", 2)[2])
            if not it: return self.send(404, {})
            files = [{"name": n, "format": "VBR MP3", "title": t, "length": l, "creator": it["creator"]} for n, t, l in it["files"]]
            files.append({"name": "cover.jpg", "format": "JPEG"})
            return self.send(200, {"metadata": {"title": it["title"], "creator": it["creator"], "licenseurl": it["lic"]}, "files": files})
        if path.startswith("/download/") or path.startswith("/jamendo-audio/"):
            return self.send(200, AUDIO, "audio/mpeg")
        if path.startswith("/services/img/"):
            return self.send(404, b"", "text/plain")
        if path == "/v3.0/tracks/":
            if q.get("client_id", [""])[0] != "demo":
                return self.send(200, {"headers": {"status": "failed", "error_message": "Your credential is not authorized."}, "results": []})
            res = [{"id": "1886257", "name": "Céu de Brigadeiro", "duration": 201, "artist_name": "Lia Sereia", "album_name": "Maré Mansa",
                    "image": "", "audio": f"{BASE}/jamendo-audio/1886257.mp3", "audiodownload": f"{BASE}/jamendo-audio/1886257.mp3",
                    "audiodownload_allowed": True, "license_ccurl": "http://creativecommons.org/licenses/by-nc-nd/3.0/", "shareurl": "https://www.jamendo.com/track/1886257"},
                   {"id": "1886258", "name": "Só no Streaming", "duration": 150, "artist_name": "Lia Sereia", "album_name": "Maré Mansa",
                    "image": "", "audio": f"{BASE}/jamendo-audio/1886258.mp3", "audiodownload": "", "audiodownload_allowed": False,
                    "license_ccurl": "http://creativecommons.org/licenses/by-nc-nd/3.0/", "shareurl": "https://www.jamendo.com/track/1886258"}]
            return self.send(200, {"headers": {"status": "success", "results_count": len(res)}, "results": res})
        self.send(404, {})

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
