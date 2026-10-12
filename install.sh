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
SKILLS="agent-test investigation prompt-adjust tools-update conversation-cleanup datastore-add datastore-tags api-call contacts conversation-actions agent-admin artifacts crm dispatches whatsapp integrations tags mercadolivre"

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
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\conversation-cleanup\" -Target \"$REPO_DIR\conversation-cleanup\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\datastore-add\" -Target \"$REPO_DIR\datastore-add\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\datastore-tags\" -Target \"$REPO_DIR\datastore-tags\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\api-call\" -Target \"$REPO_DIR\api-call\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\contacts\" -Target \"$REPO_DIR\contacts\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\conversation-actions\" -Target \"$REPO_DIR\conversation-actions\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\agent-admin\" -Target \"$REPO_DIR\agent-admin\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\artifacts\" -Target \"$REPO_DIR\artifacts\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\crm\" -Target \"$REPO_DIR\crm\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\dispatches\" -Target \"$REPO_DIR\dispatches\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\whatsapp\" -Target \"$REPO_DIR\whatsapp\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\integrations\" -Target \"$REPO_DIR\integrations\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\tags\" -Target \"$REPO_DIR\tags\""
  echo "   New-Item -ItemType Junction -Path \"\$env:USERPROFILE\.pi\agent\skills\mercadolivre\" -Target \"$REPO_DIR\mercadolivre\""
  echo ""
  echo "   Ou copie as pastas (não precisa de admin):"
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\agent-test\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\investigation\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\prompt-adjust\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\tools-update\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\conversation-cleanup\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\datastore-add\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\datastore-tags\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\api-call\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\contacts\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\conversation-actions\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\agent-admin\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\artifacts\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\crm\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\dispatches\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\whatsapp\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\integrations\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\tags\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo "   Copy-Item -Recurse -Force \"$REPO_DIR\mercadolivre\" \"\$env:USERPROFILE\.pi\agent\skills\""
  echo ""
  exit 0
fi

# Linux / macOS
case "$MODE" in
  --symlink|-s)
    echo "Modo: link simbólico (recomendado)"
    echo "  → alterações no repo refletem automaticamente no pi"
    echo ""
    for skill in $SKILLS; do
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
    for skill in $SKILLS; do
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
