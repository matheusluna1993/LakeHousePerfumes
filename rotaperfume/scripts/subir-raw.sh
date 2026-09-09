#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
  echo "uso: $0 <profile>" >&2
  exit 2
fi

CATALOG="${DATABRICKS_CATALOG:-lakehouse_rotaperfume}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATA_DIR="$REPO_ROOT/dados"

if [[ ! -d "$DATA_DIR" ]]; then
  GENERATOR="$REPO_ROOT/material/gerar_dataset.py"
  if [[ ! -f "$GENERATOR" ]]; then
    echo "dados/ não existe e o gerador não foi encontrado em $GENERATOR" >&2
    exit 1
  fi
  (cd "$REPO_ROOT" && python3 material/gerar_dataset.py --saida ./dados --seed 42)
fi

for SYSTEM in erp crm; do
  SOURCE="$DATA_DIR/$SYSTEM"
  if [[ ! -d "$SOURCE" ]]; then
    echo "diretório esperado não encontrado: $SOURCE" >&2
    exit 1
  fi
  databricks fs cp --recursive --overwrite \
    "$SOURCE" "dbfs:/Volumes/${CATALOG}/bronze/raw/${SYSTEM}" \
    --profile "$PROFILE"
done