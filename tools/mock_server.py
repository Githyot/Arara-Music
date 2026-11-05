#!/usr/bin/env python3
"""Tiny fake Subsonic + Jellyfin server for testing Arara's remote sources.

    python3 tools/mock_server.py --port 4533 --audio song.mp3 --covers dir/ [--albums 30]

Subsonic API under /rest/*, Jellyfin API under /Users, /Items, /Audio, /System.
User "demo", password "demo". Every track streams the same audio file; covers
are taken round-robin from the JPEGs in --covers. Not a real server: only
what Arara calls is implemented.
"""
import argparse, hashlib, json, os, random, urllib.parse
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

USER, PASSWORD, TOKEN, UID = "demo", "demo", "jf-token-123", "u1"
WORDS = ["Céu", "Mar", "Lua", "Sol", "Rio", "Vento", "Areia", "Noite", "Saudade", "Caminho", "Estrela", "Chuva",
         "Janela", "Ponte", "Cidade", "Sertão", "Varanda", "Aurora", "Farol", "Maré", "Cais", "Brisa"]
ARTISTS = ["Os Tucanos", "Maria Bonita", "Trio Ipê", "Banda Jacarandá", "Lia Sereia", "Coral do Cerrado",
           "João do Pandeiro", "As Seriemas", "Quarteto Mangue", "Duo Garoa"]


def build(n_albums, seed):
    rnd = random.Random(seed)
    albums, tracks = [], []
    for a in range(n_albums):
        artist = ARTISTS[a % len(ARTISTS)]
        title = f"{rnd.choice(WORDS)} {rnd.choice(['de', 'sem', 'do', 'e'])} {rnd.choice(WORDS)}"
        al = {"id": f"al-{a}", "name": title, "artist": artist, "year": 1970 + rnd.randrange(50), "cover": a, "songs": []}
        for t in range(1, rnd.randrange(8, 13)):
            tr = {"id": f"tr-{a}-{t}", "title": f"{rnd.choice(WORDS)} {rnd.choice(WORDS).lower()}", "artist": artist,
                  "album": title, "albumId": al["id"], "track": t, "disc": 1, "year": al["year"],
                  "duration": rnd.randrange(120, 330)}
            al["songs"].append(tr); tracks.append(tr)
        albums.append(al)
    return albums, tracks


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def sub(self, payload, ok=True):
        r = {"status": "ok" if ok else "failed", "version": "1.16.1", "type": "navidrome", "openSubsonic": True}
        r.update(payload)
        self.send(200, {"subsonic-response": r})

    def song(self, t):
        return {"id": t["id"], "title": t["title"], "artist": t["artist"], "album": t["album"], "albumId": t["albumId"],
                "coverArt": t["albumId"], "track": t["track"], "discNumber": t["disc"], "year": t["year"],
                "duration": t["duration"], "displayAlbumArtist": t["artist"], "isDir": False}

    def item(self, t):
        return {"Id": t["id"], "Name": t["title"], "Artists": [t["artist"]], "AlbumArtist": t["artist"], "Album": t["album"],
                "AlbumId": t["albumId"], "AlbumPrimaryImageTag": "tag", "IndexNumber": t["track"],
                "ParentIndexNumber": t["disc"], "ProductionYear": t["year"], "RunTimeTicks": t["duration"] * 10_000_000,
                "Type": "Audio"}

    def cover(self, album_id):
        al = next((a for a in self.server.albums if a["id"] == album_id), None)
        if not al:
            return self.send(404, b"", "text/plain")
        self.send(200, self.server.covers[al["cover"] % len(self.server.covers)], "image/jpeg")

    def audio(self):
        self.send(200, self.server.audio, "audio/mpeg")

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query, keep_blank_values=True).items()}
        p = u.path
        if p.startswith("/rest/"):
            m = p[6:].removesuffix(".view")
            tok = hashlib.md5((PASSWORD + q.get("s", "")).encode()).hexdigest()
            if q.get("u") != USER or q.get("t") != tok:
                return self.sub({"error": {"code": 40, "message": "Wrong username or password"}}, ok=False)
            if m == "ping":
                return self.sub({})
            if m == "search3":
                off, n = int(q.get("songOffset", 0)), int(q.get("songCount", 20))
                words = q.get("query", "").strip('"').lower()
                pool = [t for t in self.server.tracks if words in t["title"].lower()] if words else self.server.tracks
                return self.sub({"searchResult3": {"song": [self.song(t) for t in pool[off:off + n]]}})
            if m == "getAlbumList2":
                off, n = int(q.get("offset", 0)), int(q.get("size", 10))
                return self.sub({"albumList2": {"album": [{"id": a["id"], "name": a["name"], "artist": a["artist"]} for a in self.server.albums[off:off + n]]}})
            if m == "getAlbum":
                a = next(a for a in self.server.albums if a["id"] == q["id"])
                return self.sub({"album": {"id": a["id"], "name": a["name"], "artist": a["artist"], "song": [self.song(t) for t in a["songs"]]}})
            if m == "getCoverArt":
                return self.cover(q.get("id"))
            if m == "stream":
                return self.audio()
            return self.sub({"error": {"code": 0, "message": "not implemented"}}, ok=False)

        if p == "/System/Info/Public":
            return self.send(200, {"ServerName": "Jellyfin de Teste", "Version": "10.10.0"})
        auth = self.headers.get("Authorization", "") + self.headers.get("X-Emby-Token", "")
        authed = TOKEN in auth or q.get("api_key") == TOKEN
        if p.startswith("/Audio/") and p.endswith("/stream"):
            return self.audio() if authed else self.send(401, b"", "text/plain")
        if not authed:
            return self.send(401, b"", "text/plain")
        if p == f"/Users/{UID}/Items":
            start, lim = int(q.get("StartIndex", 0)), int(q.get("Limit", 100))
            return self.send(200, {"Items": [self.item(t) for t in self.server.tracks[start:start + lim]],
                                   "TotalRecordCount": len(self.server.tracks), "StartIndex": start})
        if p.startswith("/Items/") and p.endswith("/Images/Primary"):
            return self.cover(p.split("/")[2])
        self.send(404, b"", "text/plain")

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)) or 0)
        if self.path == "/Users/AuthenticateByName":
            d = json.loads(body or b"{}")
            if d.get("Username") == USER and d.get("Pw") == PASSWORD and "MediaBrowser" in self.headers.get("Authorization", ""):
                return self.send(200, {"AccessToken": TOKEN, "User": {"Id": UID, "Name": USER}})
            return self.send(401, b"", "text/plain")
        self.send(404, b"", "text/plain")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=4533)
    ap.add_argument("--audio", required=True)
    ap.add_argument("--covers", required=True)
    ap.add_argument("--albums", type=int, default=30)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    srv.albums, srv.tracks = build(a.albums, a.seed)
    srv.audio = open(a.audio, "rb").read()
    srv.covers = [open(os.path.join(a.covers, f), "rb").read() for f in sorted(os.listdir(a.covers)) if f.endswith(".jpg")]
    print(f"mock em http://127.0.0.1:{a.port}: {len(srv.albums)} álbuns, {len(srv.tracks)} faixas", flush=True)
    srv.serve_forever()
