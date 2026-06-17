#!/usr/bin/env bash
# Chatvolt Skills Installer
# Instala as skills no ~/.pi/agent/skills/
# Uso: ./install.sh [--symlink|--copy]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_SKILLS_DIR="$HOME/.pi/agent/skills"
MODE="${1:---symlink}"

mkdir -p "$PI_SKILLS_DIR"

echo "Instalando Chatvolt Skills no pi..."
echo "  Destino: $PI_SKILLS_DIR"
echo ""

case "$MODE" in
  --symlink|-s)
    echo "Modo: link simbólico (recommendado)"
    echo "  → alterações no repo refletem automaticamente no pi"
    for skill in agent-test investigation prompt-adjust tools-update; do
      target="$PI_SKILLS_DIR/$skill"
      [ -L "$target" ] && rm "$target"
      [ -d "$target" ] && rm -rf "$target"
      ln -s "$REPO_DIR/$skill" "$target"
      echo "  ✅ $skill → $target"
    done
    ;;
  --copy|-c)
    echo "Modo: cópia"
    echo "  → skills independentes do repo"
    for skill in agent-test investigation prompt-adjust tools-update; do
      target="$PI_SKILLS_DIR/$skill"
      [ -d "$target" ] && rm -rf "$target"
      cp -r "$REPO_DIR/$skill" "$target"
      echo "  ✅ $skill copiada"
    done
    ;;
  *)
    echo "Uso: $0 [--symlink|--copy]"
    echo "  --symlink (padrão): cria links simbólicos"
    echo "  --copy:             copia os arquivos"
    exit 1
    ;;
esac

echo ""
echo "🎯 Skills instaladas! O pi já vai reconhecê-las."
echo ""
echo "Próximo passo: configure suas variáveis de ambiente"
echo "  export CHATVOLT_API_KEY='sk-...'"
echo "  export CHATVOLT_AGENT_ID='cminahdll02m496hey09nozu8'"
echo ""
echo "Depois é só conversar com o pi! 🚀"
