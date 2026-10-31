"""Lecture seule de la base locale de T3 Code, pour relier les worktrees CSGO aux threads T3.

Usage :
  python -I t3_threads.py thread-of <claude_session_id>   -> id du thread T3 qui reprend cette session (vide si aucun)
  python -I t3_threads.py status <thread_id> [...]         -> JSON {thread_id: active|settled|archived|deleted|missing}

T3 stocke ses threads dans statev2.sqlite (orchestration v2) ; l'ancienne base state.sqlite n'est plus alimentee
depuis la migration et ne sert plus que de repli pour les threads anterieurs.
"""

import json
import sqlite3
import sys
from pathlib import Path

USERDATA = Path.home() / ".t3" / "userdata"
DB_V2 = USERDATA / "statev2.sqlite"
DB_V1 = USERDATA / "state.sqlite"


def connect(db):
    """Cette methode permet d'ouvrir une base T3 en lecture seule lorsque T3 tourne (mode WAL) ; None si elle est absente."""
    if not db.exists():
        return None
    return sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True)


def thread_of_v2(conn, session_id):
    """Cette methode permet de retrouver, dans la base v2, le thread T3 dont le fil fournisseur porte la session Claude donnee."""
    row = conn.execute(
        "select thread_id from orchestration_v2_projection_provider_threads"
        " where json_extract(payload_json, '$.nativeThreadRef.nativeId') = ?",
        (session_id,),
    ).fetchone()
    return row[0] if row else ""


def thread_of_v1(conn, session_id):
    """Cette methode permet de retrouver, dans l'ancienne base, le thread T3 qui reprend une session Claude donnee."""
    for thread_id, cursor in conn.execute("select thread_id, resume_cursor_json from provider_session_runtime"):
        try:
            if json.loads(cursor or "{}").get("resume") == session_id:
                return thread_id
        except ValueError:
            continue
    return ""


def status_v2(conn, thread_id):
    """Cette methode permet de connaitre l'etat d'un thread dans la base v2 ;
    un thread settled puis rouvert (unsettledAt posterieur) redevient actif. None si le thread y est absent."""
    row = conn.execute(
        "select payload_json from orchestration_v2_projection_threads where thread_id = ?", (thread_id,)
    ).fetchone()
    if row is None:
        return None
    t = json.loads(row[0] or "{}")
    if t.get("deletedAt"):
        return "deleted"
    if t.get("archivedAt"):
        return "archived"
    settled_at = t.get("settledAt")
    unsettled_at = t.get("unsettledAt")
    if t.get("settledOverride") == "settled" and settled_at and (not unsettled_at or unsettled_at <= settled_at):
        return "settled"
    return "active"


def status_v1(conn, thread_id):
    """Cette methode permet de connaitre l'etat d'un thread dans l'ancienne base ;
    un thread settled qui a recu un message depuis redevient actif."""
    row = conn.execute(
        "select archived_at, deleted_at, settled_override, settled_at, latest_user_message_at"
        " from projection_threads where thread_id = ?",
        (thread_id,),
    ).fetchone()
    if row is None:
        return "missing"
    if row[1]:
        return "deleted"
    if row[0]:
        return "archived"
    if row[2] == "settled" and row[3] and (not row[4] or row[4] <= row[3]):
        return "settled"
    return "active"


def main(args):
    """Cette methode permet d'executer la commande demandee en interrogeant la base v2 puis, a defaut, l'ancienne base."""
    v2, v1 = connect(DB_V2), connect(DB_V1)
    if args[0] == "thread-of":
        found = (v2 and thread_of_v2(v2, args[1])) or (v1 and thread_of_v1(v1, args[1])) or ""
        print(found)
    elif args[0] == "status":
        out = {}
        for thread_id in args[1:]:
            state = status_v2(v2, thread_id) if v2 else None
            out[thread_id] = state or (status_v1(v1, thread_id) if v1 else "missing")
        print(json.dumps(out))


if __name__ == "__main__":
    if len(sys.argv) >= 3:
        main(sys.argv[1:])
