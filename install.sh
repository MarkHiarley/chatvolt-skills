#!/usr/bin/env bash
# Chatvolt Skills Installer
# Instala as skills no ~/.pi/agent/skills/
#
# Uso:
#   Linux/macOS: ./install.sh [--symlink|--copy]
#   Windows:     Use PowerShell (veja README.md)
#
# Se você estiver no Windows, use Git Bash ou WSL para rodar este script,
# ou siga as instruções de instalação manual no README.md (seção Windows)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PI_SKILLS_DIR="$HOME/.pi/agent/skills"
MODE="${1:---symlink}"

mkdir -p "$PI_SKILLS_DIR"

echo "========================================"
echo " Chatvolt Skills Installer"
echo "========================================"
echo "  Repositório: $REPO_DIR"
echo "  Destino:     $PI_SKILLS_DIR"
echo "  Modo:        $MODE"
echo ""

# Detect Windows (Git Bash / WSL)
if [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]]; then
  echo "⚠️  Windows detectado (Git Bash)"
  echo "   Recomendo usar PowerShell como Administrador:"
  echo ""
  echo "   New-Item -ItemType Directory -Force -Path \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\agent-test\" -Target \"$REPO_DIR\agent-test\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\investigation\" -Target \"$REPO_DIR\investigation\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\prompt-adjust\" -Target \"$REPO_DIR\prompt-adjust\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\tools-update\" -Target \"$REPO_DIR\tools-update\""
  echo ""
  echo "   Ou copie as pastas (não precisa de admin):"
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\agent-test\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\investigation\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\prompt-adjust\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\tools-update\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo ""
  exit 0
fi

# Linux / macOS
case "$MODE" in
  --symlink|-s)
    echo "Modo: link simbólico (recomendado)"
    echo "  → alterações no repo refletem automaticamente no pi"
    echo ""
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
    echo ""
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
echo "========================================"
echo "🎯 Skills instaladas com sucesso!"
echo "========================================"
echo ""
echo "O pi já vai reconhecê-las automaticamente."
echo ""
echo "Próximo passo: configure suas variáveis de ambiente"
echo ""
echo "  Linux/macOS (~/.bashrc ou ~/.zshrc):"
echo "    export CHATVOLT_API_KEY='sk-...'"
echo "    export CHATVOLT_AGENT_ID='seu-agent-id'"
echo ""
echo "  Windows PowerShell (\$PROFILE):"
echo "    \$env:CHATVOLT_API_KEY = 'sk-...'"
echo "    \$env:CHATVOLT_AGENT_ID = 'seu-agent-id'"
echo ""
echo "Depois é só conversar com o pi! 🚀"
echo "  Ex: 'pi, testa o agente padrão'"
