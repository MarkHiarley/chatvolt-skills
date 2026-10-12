#!/usr/bin/env bash
# catalog.sh — índice de TUDO que a API pública do Chatvolt expõe.
#
# Lê data/endpoints.json (gerado do openapi.yaml publicado em 2026-10-12) e
# mostra método, caminho, grupo e disponibilidade medida ao vivo.
set -euo pipefail

source "$(dirname "$0")/_lib.sh"

DATA="$(dirname "$0")/../data/endpoints.json"

usage() {
  cat <<'EOF'
Uso: catalog.sh [--group <grupo>] [--filter <regex>] [--available-only] [--list-groups]

  --group <g>        mostra só um grupo (agents, conversations, crm, dispatches, …)
  --filter <regex>   filtra por método+caminho (case-insensitive)
  --available-only   esconde rotas que respondem 404 no ambiente atual
  --list-groups      lista os grupos com contagem
  -h, --help         mostra esta ajuda
EOF
}

GROUP=""; FILTER=""; AVAILABLE_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --group)          GROUP="${2:?--group exige o nome do grupo}"; shift 2 ;;
    --filter)         FILTER="${2:?--filter exige uma regex}"; shift 2 ;;
    --available-only) AVAILABLE_ONLY=1; shift ;;
    --list-groups)    GROUP="__LIST__"; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) cv_die "opção desconhecida: $1 (use -h para a ajuda)" ;;
  esac
done

[ -f "$DATA" ] || cv_die "catálogo não encontrado em $DATA"

python3 - "$DATA" "$GROUP" "$FILTER" "$AVAILABLE_ONLY" <<'PY'
import json, re, sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
group, pattern, available_only = sys.argv[2], sys.argv[3], sys.argv[4] == "1"
ops = data["operations"]

if group == "__LIST__":
    counts = {}
    for op in ops:
        counts[op["group"]] = counts.get(op["group"], 0) + 1
    print(f"{'GRUPO':<26} OPERAÇÕES")
    for name in sorted(counts):
        print(f"{name:<26} {counts[name]:>3}")
    print(f"\ntotal: {len(ops)} operações em {len(counts)} grupos")
    print(f"base URL: {data['base_url']}  ·  verificado em {data['checked_at']}")
    raise SystemExit

sel = ops
if group:
    sel = [o for o in sel if o["group"] == group]
if pattern:
    rx = re.compile(pattern, re.I)
    sel = [o for o in sel if rx.search(o["method"] + " " + o["path"])]
if available_only:
    sel = [o for o in sel if o["availability"].startswith("disponível")]

if not sel:
    print("nenhuma operação corresponde ao filtro.", file=sys.stderr)
    raise SystemExit(1)

w = max(len(o["path"]) for o in sel)
print(f"{'MÉTODO':<7} {'CAMINHO':<{w}}  DISPONIBILIDADE")
for o in sorted(sel, key=lambda x: (x["group"], x["path"], x["method"])):
    print(f"{o['method']:<7} {o['path']:<{w}}  {o['availability']}")
print(f"\n{len(sel)} de {len(ops)} operações  ·  base {data['base_url']}")
for note in data.get("notes", []):
    print(f"· {note}")
PY
