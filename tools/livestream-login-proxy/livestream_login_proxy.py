#!/usr/bin/env python3
"""HTTP login front for RoT.

The upstream login-server does not know the "@livestream" spectator account,
which Canary only handles in its binary login protocol. This proxy answers
"@livestream" logins with the list of players that are broadcasting right now
and forwards every other request unchanged to the real login-server.

The game server validates the session key "@livestream\\n<password>" itself,
so this proxy only builds the character list shown to spectators.
"""

import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN_HOST = os.environ.get("PROXY_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("PROXY_LISTEN_PORT", "8088"))
UPSTREAM = os.environ.get("PROXY_UPSTREAM", "http://127.0.0.1:8089")
MAX_BODY = 64 * 1024
LIVESTREAM_ACCOUNT = "@livestream"
STATUS_OPEN = 1
STATUS_PASSWORD = 3

VOCATIONS = {
    0: "None", 1: "Sorcerer", 2: "Druid", 3: "Paladin", 4: "Knight",
    5: "Master Sorcerer", 6: "Elder Druid", 7: "Royal Paladin", 8: "Elite Knight",
    9: "Monk", 10: "Exalted Monk",
}

CASTERS_QUERY = (
    "SELECT p.name, p.level, p.vocation, p.looktype, p.lookhead, p.lookbody, "
    "p.looklegs, p.lookfeet, p.lookaddons "
    "FROM active_livestream_casters c "
    "JOIN players p ON p.id = c.caster_id "
    "JOIN players_online o ON o.player_id = p.id "
    "WHERE c.livestream_status IN ({statuses}) "
    "ORDER BY c.livestream_viewers DESC, p.name LIMIT 100"
)


def fetch_casters(with_password: bool) -> list[dict]:
    statuses = f"{STATUS_OPEN},{STATUS_PASSWORD}" if with_password else str(STATUS_OPEN)
    env = dict(os.environ, MYSQL_PWD=os.environ["MYSQL_PASS"])
    result = subprocess.run(
        [
            "mysql", "--batch", "--skip-column-names",
            "-h", os.environ.get("MYSQL_HOST", "127.0.0.1"),
            "-P", os.environ.get("MYSQL_PORT", "3306"),
            "-u", os.environ["MYSQL_USER"],
            os.environ["MYSQL_DBNAME"],
            "-e", CASTERS_QUERY.format(statuses=statuses),
        ],
        capture_output=True, text=True, timeout=5, env=env, check=True,
    )
    casters = []
    for line in result.stdout.splitlines():
        cols = line.split("\t")
        if len(cols) != 9:
            continue
        name, level, vocation, looktype, head, body, legs, feet, addons = cols
        casters.append({
            "worldid": 0,
            "name": name,
            "level": int(level),
            "vocation": VOCATIONS.get(int(vocation), "None"),
            "ismale": True,
            "ishidden": False,
            "ismaincharacter": False,
            "tutorial": False,
            "dailyrewardstate": 0,
            "outfitid": int(looktype),
            "headcolor": int(head),
            "torsocolor": int(body),
            "legscolor": int(legs),
            "detailcolor": int(feet),
            "addonsflags": int(addons),
        })
    return casters


def livestream_response(password: str) -> dict:
    casters = fetch_casters(with_password=password != "")
    if not casters:
        return {"errorCode": 3, "errorMessage": "No hay jugadores transmitiendo en este momento."}
    now = int(time.time())
    return {
        "session": {
            "sessionkey": f"{LIVESTREAM_ACCOUNT}\n{password}",
            "lastlogintime": now,
            "ispremium": False,
            "premiumuntil": 0,
            "status": "active",
            "returnernotification": False,
            "showrewardnews": False,
            "isreturner": False,
            "fpstracking": False,
            "optiontracking": False,
            "tournamentticketpurchasestate": 0,
            "emailcoderequest": False,
        },
        "playdata": {
            "worlds": [{
                "id": 0,
                "name": os.environ.get("SERVER_NAME", "RoT"),
                "externaladdress": os.environ["SERVER_IP"],
                "externalport": int(os.environ.get("SERVER_PORT", "7172")),
                "externaladdressprotected": os.environ["SERVER_IP"],
                "externalportprotected": int(os.environ.get("SERVER_PORT", "7172")),
                "externaladdressunprotected": os.environ["SERVER_IP"],
                "externalportunprotected": int(os.environ.get("SERVER_PORT", "7172")),
                "previewstate": 0,
                "location": os.environ.get("SERVER_LOCATION", "BRA"),
                "anticheatprotection": False,
                "pvptype": 0,
                "istournamentworld": False,
                "restrictedstore": False,
                "currenttournamentphase": 2,
            }],
            "characters": casters,
        },
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # keep journald quiet
        pass

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _forward(self, method: str, body: bytes | None) -> None:
        headers = {k: v for k, v in self.headers.items()
                   if k.lower() not in ("host", "content-length", "connection")}
        headers["X-Forwarded-For"] = self.client_address[0]
        request = urllib.request.Request(UPSTREAM + self.path, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                self._send(response.status, response.read(), response.headers.get("Content-Type", "application/json"))
        except urllib.error.HTTPError as error:
            self._send(error.code, error.read(), error.headers.get("Content-Type", "application/json"))
        except Exception:
            self._send(502, b'{"errorCode":3,"errorMessage":"Login server unavailable."}')

    def do_GET(self):
        self._forward("GET", None)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length < 0 or length > MAX_BODY:
            self._send(413, b'{"errorCode":3,"errorMessage":"Request too large."}')
            return
        body = self.rfile.read(length)
        try:
            payload = json.loads(body or b"{}")
        except ValueError:
            payload = None
        if (isinstance(payload, dict) and payload.get("type") == "login"
                and str(payload.get("email", "")).strip().lower() == LIVESTREAM_ACCOUNT):
            try:
                response = livestream_response(str(payload.get("password") or ""))
            except Exception:
                response = {"errorCode": 3, "errorMessage": "Livestream list unavailable."}
            self._send(200, json.dumps(response).encode())
            return
        self._forward("POST", body)


if __name__ == "__main__":
    ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler).serve_forever()
