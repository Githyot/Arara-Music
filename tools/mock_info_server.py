#!/usr/bin/env python3
"""Fake MusicBrainz + Wikidata + Wikipedia for testing the info pages offline.

Run:  python3 tools/mock_info_server.py 8099
App:  ARARA_MB_URL=http://127.0.0.1:8099 ARARA_WIKIDATA_URL=http://127.0.0.1:8099 \
      ARARA_WIKI_URL=http://127.0.0.1:8099 arara-music

Answers every search with a hit named after the query, so any (fictional)
test library gets credits, a bio and a photo. All data here is made up.
"""
import json, re, sys, subprocess, os, tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
BASE = f"http://127.0.0.1:{PORT}"
PHOTO = os.path.join(tempfile.gettempdir(), "arara-mock-photo.jpg")
if not os.path.exists(PHOTO):
    subprocess.run(["convert", "-size", "400x400", "radial-gradient:#f6d365-#5e3a8c", "-fill", "#ffffff40",
                    "-draw", "circle 200,170 200,95", "-draw", "ellipse 200,400 140,130 180,360", PHOTO], check=False)

def phrase(q, field):
    m = re.search(field + r':"((?:[^"\\]|\\.)*)"', q)
    return re.sub(r"\\(.)", r"\1", m.group(1)) if m else ""

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, obj, ctype="application/json"):
        body = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
        self.send_response(200); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path); q = parse_qs(u.query).get("query", [""])[0]; p = u.path
        if p == "/ws/2/artist/" and "tag:" in q:
            # "Similares": artists filed under a tag (made-up names, one already in the test library).
            t = phrase(q, "tag"); area = phrase(q, "area")
            names = [("Os Coqueiros", "Group", "Brazil"), ("Banda Vento Sul", "Group", "Brazil"), ("Clara Duarte", "Person", "Brazil"),
                     ("Trio Areia Fina", "Group", "Brazil"), ("Rafa Monteiro", "Person", "Brazil"), ("Coletivo Farol", "Group", "Brazil")]
            if not area:
                names += [("The Paper Lanterns", "Group", "United Kingdom"), ("Mira Halvorsen", "Person", "Norway"), ("Static Orchard", "Group", "United States")]
            return self.send({"artists": [{"id": "tag-" + n.replace(" ", "_"), "name": n, "type": ty, "area": {"name": ar}, "score": 100} for n, ty, ar in names]})
        if p == "/ws/2/artist/":
            n = phrase(q, "artist"); return self.send({"artists": [{"id": "art-" + n.replace(" ", "_"), "name": n, "score": 100}]})
        if p.startswith("/ws/2/artist/"):
            n = unquote(p.split("/")[-1][4:]).replace("_", " ")
            group = "Banda" in n
            return self.send({"id": p.split("/")[-1], "name": n, "type": "Group" if group else "Person",
                "disambiguation": "", "area": {"name": "Brasil"}, "begin-area": {"name": "Recife" if group else "Salvador"},
                "life-span": {"begin": "2009-05-02" if group else "1991-08-14", "ended": False},
                "genres": ([{"name": "alternative rock", "count": 5}, {"name": "rock", "count": 4}, {"name": "brazilian", "count": 2}, {"name": "mpb", "count": 1}] if group else
                           [{"name": "mpb", "count": 5}, {"name": "pop brasileiro", "count": 3}, {"name": "folk", "count": 1}]),
                "relations": [{"type": "wikidata", "url": {"resource": "https://www.wikidata.org/wiki/Q42" + str(len(n))}}]})
        if p.startswith("/wiki/Special:EntityData/"):
            qid = p.split("/")[-1][:-5]
            return self.send({"entities": {qid: {"sitelinks": {"ptwiki": {"title": "Artista " + qid}}}}})
        if p.startswith("/api/rest_v1/page/summary/"):
            return self.send({"extract": "Personagem fictício usado nos testes do Arara Music. Começou tocando em bares e festivais independentes, "
                "lançou discos por um selo pequeno e ficou conhecido pelas letras sobre o litoral e a vida no interior. "
                "Os dados desta página vêm de um servidor de teste e não descrevem ninguém de verdade; com internet, "
                "o aplicativo mostra aqui o resumo da Wikipédia em português e, se não houver, em inglês.",
                "content_urls": {"desktop": {"page": "https://pt.wikipedia.org/wiki/Teste"}},
                "thumbnail": {"source": BASE + "/photo.jpg"}})
        if p == "/photo.jpg":
            return self.send(open(PHOTO, "rb").read(), "image/jpeg")
        if p == "/ws/2/release/":
            t = phrase(q, "release"); return self.send({"releases": [{"id": "rel-" + t.replace(" ", "_"), "title": t, "status": "Official", "score": 100}]})
        if p.startswith("/ws/2/release/"):
            t = unquote(p.split("/")[-1][4:]).replace("_", " ")
            return self.send({"id": p.split("/")[-1], "title": t, "date": "2021-03-12", "country": "BR", "barcode": "7891234567895",
                "label-info": [{"catalog-number": "PDR-021", "label": {"name": "Selo Pindorama"}}],
                "release-group": {"id": "rg1", "primary-type": "Album", "secondary-types": [], "first-release-date": "2021-03-12", "genres": []},
                "genres": [{"name": "mpb", "count": 4}, {"name": "nova mpb", "count": 2}], "media": [{"format": "Digital Media"}],
                "relations": [{"type": "wikidata", "url": {"resource": "https://www.wikidata.org/wiki/Q900"}}]})
        if p == "/ws/2/recording/":
            t = phrase(q, "recording"); return self.send({"recordings": [{"id": "rec-" + t.replace(" ", "_"), "title": t, "score": 100, "length": 200000}]})
        if p.startswith("/ws/2/recording/"):
            t = unquote(p.split("/")[-1][4:]).replace("_", " ")
            return self.send({"id": p.split("/")[-1], "title": t, "first-release-date": "2021-03-12", "isrcs": ["BRXYZ2100001"],
                "artist-credit": [{"name": "Lia Moreno", "artist": {"id": "a1", "name": "Lia Moreno"}}],
                "genres": [{"name": "mpb", "count": 3}],
                "relations": [
                    {"target-type": "artist", "type": "vocal", "attributes": ["lead vocals"], "artist": {"id": "a1", "name": "Lia Moreno"}},
                    {"target-type": "artist", "type": "vocal", "attributes": ["background vocals"], "artist": {"id": "a3", "name": "Bia Fontes"}},
                    {"target-type": "artist", "type": "instrument", "attributes": ["acoustic guitar"], "artist": {"id": "a2", "name": "Davi Rocha"}},
                    {"target-type": "artist", "type": "instrument", "attributes": ["percussion"], "artist": {"id": "a4", "name": "Jonas Pereira"}},
                    {"target-type": "artist", "type": "mastering", "attributes": [], "artist": {"id": "a5", "name": "Nina Barros"}},
                    {"target-type": "recording", "type": "samples material", "direction": "forward",
                     "recording": {"title": "Ciranda Antiga", "artist-credit": [{"name": "Quarteto Mangue"}]}},
                    {"target-type": "work", "type": "performance", "work": {"relations": [
                        {"target-type": "artist", "type": "composer", "attributes": [], "artist": {"id": "a1", "name": "Lia Moreno"}},
                        {"target-type": "artist", "type": "lyricist", "attributes": [], "artist": {"id": "a6", "name": "Paulo Vieira"}}]}},
                ]})
        self.send_response(404); self.end_headers()

ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
