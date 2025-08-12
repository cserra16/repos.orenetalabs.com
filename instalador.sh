#!/usr/bin/env bash
set -euo pipefail

WEB_DIR="/var/www/tools.orenetalabs.com"
VENV_DIR="$WEB_DIR/venv"
SCRIPT_FILE="$WEB_DIR/ingest_starred.py"
INDEX_FILE="$WEB_DIR/index.html"

echo "=== Instalador indexador de repos (GitHub Stars) + Web estática ==="

# 1) Crear carpeta destino con permisos del usuario actual
if [ ! -d "$WEB_DIR" ]; then
  echo "[INFO] Creando $WEB_DIR"
  sudo mkdir -p "$WEB_DIR"
  sudo chown "$USER":"$USER" "$WEB_DIR"
fi

# 2) Asegurar Python3 y venv (solo si faltan)
if ! command -v python3 >/dev/null 2>&1; then
  echo "[INFO] Instalando Python3..."
  if [ -f /etc/debian_version ]; then
    sudo apt update && sudo apt install -y python3 python3-venv
  else
    echo "[ERROR] Instala Python3 manualmente."
    exit 1
  fi
fi
if ! python3 -m venv --help >/dev/null 2>&1; then
  echo "[INFO] Instalando módulo venv..."
  sudo apt install -y python3-venv
fi

# 3) Crear/usar venv DENTRO de /var/www/... (sin sudo)
if [ ! -d "$VENV_DIR" ]; then
  echo "[INFO] Creando venv en $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

# 4) Activar venv e instalar dependencias AHÍ (sin --user, sin sudo)
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip
pip install requests

# 5) Crear script Python
cat > "$SCRIPT_FILE" <<'PYCODE'
import os, json, requests
from datetime import datetime
from time import sleep

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
USERNAME = os.getenv("GITHUB_USERNAME")
BASE_HEADERS = {
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3.star+json"
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
        for item in batch:
            repo = item.get("repo", item)
            starred_at = item.get("starred_at")
            out.append((repo, starred_at))
        page += 1
        sleep(0.3)
    return out

def main():
    if not GITHUB_TOKEN:
        raise SystemExit("Falta GITHUB_TOKEN en el entorno.")
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
    data.sort(key=lambda x: (x.get("starred_at") or x.get("last_update") or ""), reverse=True)
    with open(os.path.join(os.path.dirname(__file__), "repos.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    print(f"OK -> {len(data)} repos guardados en repos.json")

if __name__ == "__main__":
    main()
PYCODE

# 6) HTML estático
cat > "$INDEX_FILE" <<'HTML'
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Repos docentes</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 0; padding: 2rem; background:#f7f7f7; color:#333; }
  header { display:flex; gap:1rem; flex-wrap:wrap; align-items:center; }
  .grid { display:grid; grid-template-columns: repeat(auto-fill,minmax(280px,1fr)); gap:1rem; margin-top:1rem; }
  .card { background:white; border:none; border-radius:12px; padding:1.2rem; box-shadow:0 2px 4px rgba(0,0,0,0.08); display:flex; flex-direction:column; gap:.5rem; }
  .subjects { display:flex; gap:.5rem; flex-wrap:wrap; margin-top:.5rem; }
  .pill { background:#efefef; border-radius:999px; padding:.2rem .6rem; font-size:.75rem; }
  .muted { color:#666; font-size:.9rem; }
  .filters { display:flex; gap:1rem; align-items:center; flex-wrap:wrap; }
  input[type="search"]{ padding:.5rem; width:260px; }
  label { display:flex; gap:.4rem; align-items:center; }
</style>
</head>
<body>
<header>
  <h1>Repos para clase</h1>
  <div class="filters">
    <input id="q" type="search" placeholder="Buscar… (nombre, descripción, topic)"/>
    <label><input type="checkbox" name="s" value="projectes" checked> projectes</label>
    <label><input type="checkbox" name="s" value="seguretat" checked> seguretat</label>
    <label><input type="checkbox" name="s" value="alta-disponibilitat" checked> alta-disponibilitat</label>
  </div>
</header>

<div id="grid" class="grid"></div>

<script>
const state = { data: [], q: "", subjects: new Set(["projectes","seguretat","alta-disponibilitat"]) };

const $q = document.getElementById('q');
$q.addEventListener('input', () => { state.q = $q.value.toLowerCase(); render(); });

document.querySelectorAll('input[name="s"]').forEach(cb=>{
  cb.addEventListener('change', ()=>{
    if(cb.checked) state.subjects.add(cb.value); else state.subjects.delete(cb.value);
    render();
  });
});

fetch('repos.json').then(r=>r.json()).then(d=>{ state.data = d; render(); });

function match(repo){
  const subs = new Set([...(repo.subjects||[]), ...(repo.manual_subjects||[])]);
  const subjectOk = [...subs].some(s => state.subjects.has(s));
  if(!subjectOk) return false;
  if(!state.q) return true;
  const hay = [
    repo.name, repo.owner, repo.description||"",
    (repo.topics||[]).join(" "),
    (repo.languages||[]).join(" ")
  ].join(" ").toLowerCase();
  return hay.includes(state.q);
}

function card(repo){
  const subs = [...new Set([...(repo.subjects||[]), ...(repo.manual_subjects||[])])];
  return `
  <article class="card">
    <h3><a href="${repo.url}" target="_blank" rel="noopener">${repo.name}</a></h3>
    <div class="muted">${repo.owner} • ⭐ ${repo.stars} • ${repo.license}</div>
    <p>${repo.description||""}</p>
    <div class="subjects">${subs.map(s=>`<span class="pill">${s}</span>`).join("")}</div>
    <div class="muted">Actualizado: ${new Date(repo.last_update||repo.updated_at).toLocaleDateString()}</div>
  </article>`;
}

function render(){
  const grid = document.getElementById('grid');
  const items = state.data.filter(match);
  grid.innerHTML = items.map(card).join("") || "<p>No hay repos que coincidan.</p>";
}
</script>
</body>
</html>
HTML

echo "[OK] Web y venv listos en $WEB_DIR"
echo
echo "Para ejecutar ahora:"
echo "  source \"$VENV_DIR/bin/activate\""
echo "  export GITHUB_TOKEN=ghp_xxxxx"
echo "  python \"$SCRIPT_FILE\""
echo
read -p "¿Configurar cron diario a las 03:00? (s/N): " resp
if [[ "$resp" =~ ^[sS]$ ]]; then
  # Cron que activa el venv y ejecuta el script
  (crontab -l 2>/dev/null; echo "0 3 * * * cd $WEB_DIR && . $VENV_DIR/bin/activate && GITHUB_TOKEN=ghp_xxxxx python $SCRIPT_FILE >/tmp/repos_index.log 2>&1") | crontab -
  echo "[OK] Cron configurado."
fi

echo "Hecho."

