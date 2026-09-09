#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-}"
if [[ -z "$PROFILE" ]]; then
  echo "uso: $0 <profile>" >&2
  exit 2
fi

# No Free Edition, o Default Storage impede a API do Unity Catalog de criar
# catálogos sem managed location (INVALID_STATE). O comando SQL funciona.
databricks experimental aitools tools query \
  --profile "$PROFILE" \
  --sql "CREATE CATALOG IF NOT EXISTS lakehouse_rotaperfume"