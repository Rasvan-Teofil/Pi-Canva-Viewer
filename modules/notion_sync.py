import datetime
import json
import os
import urllib.error
import urllib.request
from typing import Any, Dict, List

from .config_manager import load_config, save_config


def sync_tasks_from_notion(api_token: str | None = None, database_id: str | None = None) -> Dict[str, Any]:
    """
    Optional live Notion sync for ICF Volunteer Tasks database.
    Uses standard library urllib.request so no external pip packages are required.
    """
    cfg = load_config()
    notion_cfg = cfg.get("notion", {})
    token = (api_token or os.environ.get("NOTION_TOKEN") or notion_cfg.get("api_token") or "").strip()
    db_id = (database_id or os.environ.get("NOTION_DATABASE_ID") or notion_cfg.get("database_id") or "").strip()

    if not token or not db_id:
        return {
            "ok": False,
            "error": "Kein NOTION_TOKEN oder Database-ID konfiguriert. Nutze lokale Aufgabenliste aus config/dashboard_data.json.",
            "tasks_count": len(cfg.get("tasks", [])),
        }

    url = f"https://api.notion.com/v1/databases/{db_id}/query"
    req = urllib.request.Request(
        url,
        data=json.dumps({"page_size": 25}).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {token}",
            "Notion-Version": "2022-06-28",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return {"ok": False, "error": f"Notion API HTTP {exc.code}: {exc.reason}"}
    except Exception as exc:
        return {"ok": False, "error": f"Notion API Verbindungsfehler: {exc}"}

    synced_tasks: List[Dict[str, Any]] = []
    for idx, page in enumerate(payload.get("results", []), start=1):
        props = page.get("properties", {})
        title_text = ""
        status_val = "todo"
        category_val = "Church Task"
        assignee_val = "Team"

        for prop_name, prop_obj in props.items():
            ptype = prop_obj.get("type")
            if ptype == "title":
                arr = prop_obj.get("title", [])
                title_text = "".join(t.get("plain_text", "") for t in arr).strip()
            elif ptype == "status" and prop_obj.get("status"):
                sname = prop_obj["status"].get("name", "").lower()
                if "done" in sname or "erledigt" in sname:
                    status_val = "done"
                elif "progress" in sname or "arbeit" in sname:
                    status_val = "in_progress"
                else:
                    status_val = "todo"
            elif ptype == "select" and prop_obj.get("select"):
                sname = prop_obj["select"].get("name", "")
                if "status" in prop_name.lower():
                    if "done" in sname.lower() or "erledigt" in sname.lower():
                        status_val = "done"
                    elif "arbeit" in sname.lower() or "progress" in sname.lower():
                        status_val = "in_progress"
                else:
                    category_val = sname

        if title_text:
            synced_tasks.append(
                {
                    "id": f"notion-{page.get('id', idx)[:8]}",
                    "title": title_text,
                    "category": category_val,
                    "status": status_val,
                    "priority": "medium",
                    "assignee": assignee_val,
                    "due": "Notion Sync",
                }
            )

    if synced_tasks:
        cfg["tasks"] = synced_tasks
        cfg.setdefault("notion", {})["last_sync"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        save_config(cfg)

    return {
        "ok": True,
        "synced_count": len(synced_tasks),
        "last_sync": cfg.get("notion", {}).get("last_sync"),
    }
