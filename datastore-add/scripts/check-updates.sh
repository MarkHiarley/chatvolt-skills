#!/usr/bin/env bash
# Chatvolt — check-updates
#
# Verifica se a API/doc do Chatvolt mudaram desde a última vez. Rode no início de
# cada skill (toda vez que ela é carregada). Nunca falha: sem rede ou sem o clone
# local do monorepo, só mostra um aviso. Desligue com CV_UPDATE_CHECK=0.
#
# Uso:
#   check-updates.sh

source "$(dirname "$0")/_lib.sh"

cv_check_updates
