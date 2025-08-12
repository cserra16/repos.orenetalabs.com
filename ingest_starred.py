import os, json, requests
from datetime import datetime
from time import sleep

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
USERNAME = os.getenv("GITHUB_USERNAME")  # opcional; si no está, usa /user/starred
BASE_HEADERS = {
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3.star+json"  # incluye starred_at
}

SUBJECT_RULES = {
    "seguretat": [
        "security","seguridad","crypt","tls","jwt","auth","oauth","owasp","firewall",
        "ids","ips","forensics","hash","cert","mfa","2fa","xss","sqli","hardening"
    ],
    "alta-disponibilitat": [
        "ha","high availability","cluster","replica","replication","kubernetes","k8s",
        "docker swarm","keepalived","haproxy","nginx","load balancer","failover",
        "consul","etcd","patroni","sre","autoscaling"
    ],
    "projectes": [
        "project","scaffold","template","ci","cd","devops","monorepo","starter",
        "roadmap","kanban","scrum","fullstack","backend","frontend","api"
    ],
}

def guess_subjects(text, topics):
    blob = f"{(text or '').lower()} {' '.join((topics or [])).lower()}"
    hits = {s for s,kws in SUBJECT_RULES.items() if any(kw in blob for kw in kws)}
    return sorted(hits) or ["projectes"]

def languages(owner, repo):
    url = f"https://api.github.com/repos/{owner}/{repo}/languages"
    r = requests.get(url, headers=BASE_HEADERS)
    return sorted(r.json(), key=r.json().get, reverse=True)[:3] if r.status_code == 200 else []

def fetch_repo(owner, repo):
    url = f"https://api.github.com/repos/{owner}/{repo}"
    r = requests.get(url, headers=BASE_HEADERS)
    r.raise_for_status()
    return r.json()

def fetch_starred():
    out = []
    page = 1
    while True:
        if USERNAME:
            url = f"https://api.github.com/users/{USERNAME}/starred?per_page=100&page={page}"
        else:
            url = f"https://api.github.com/user/starred?per_page=100&page={page}"
        r = requests.get(url, headers=BASE_HEADERS)
        r.raise_for_status()
        batch = r.json()
        if not batch:
            break
        # batch es una lista de objetos {starred_at, repo:{...}} por el Accept especial
        for item in batch:
            repo = item.get("repo", item)  # por si Accept cambiara
            starred_at = item.get("starred_at")
            out.append((repo, starred_at))
        page += 1
        # cortesía para no pegar a la API si son muchas páginas
        sleep(0.3)
    return out

def main():
    if not GITHUB_TOKEN:
        raise SystemExit("Falta GITHUB_TOKEN")
    starred = fetch_starred()
    data = []
    for repo_obj, starred_at in starred:
        owner = repo_obj["owner"]["login"]
        name = repo_obj["name"]
        meta = fetch_repo(owner, name)
        topics = meta.get("topics", [])
        desc = meta.get("description") or ""
        langs = languages(owner, name)
        subjects = guess_subjects(desc, topics)
        data.append({
            "id": f"{owner}/{name}",
            "name": meta["name"],
            "owner": owner,
            "url": meta["html_url"],
            "description": desc,
            "topics": topics,
            "license": (meta.get("license") or {}).get("spdx_id") or "NOASSERTION",
            "stars": meta.get("stargazers_count", 0),
            "last_update": meta.get("pushed_at"),
            "languages": langs,
            "subjects": subjects,
            "manual_subjects": [],
            "starred_at": starred_at,
            "updated_at": datetime.utcnow().isoformat() + "Z"
        })
    # ordena por fecha que les diste estrella (si existe), si no por pushed_at
    data.sort(key=lambda x: (x.get("starred_at") or x.get("last_update") or ""), reverse=True)
    with open("repos.json","w",encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"OK -> {len(data)} repos a repos.json")

if __name__ == "__main__":
    main()

