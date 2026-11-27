#!/usr/bin/env bash
# ============================================================
# scripts/setup-branch-protection.sh (EV3 - IE5)
# Configura la protección de la rama main por código (GitHub CLI),
# de modo que quede documentada y reproducible.
#
# Requisitos: gh autenticado (gh auth login) con permisos de administrador del repo.
# Nota: en repositorios PRIVADOS, GitHub exige plan Pro/Team para branch protection.
#
# Uso:  bash scripts/setup-branch-protection.sh <dueño/repo>
#       ENFORCE_ADMINS=true bash scripts/setup-branch-protection.sh karlahp/order-manager-eva02
# ============================================================
set -euo pipefail

REPO="${1:?Uso: $0 <dueño/repo>}"
ENFORCE_ADMINS="${ENFORCE_ADMINS:-false}"

# Los nombres deben coincidir EXACTAMENTE con el campo "name:" de cada job en ci-cd.yml
gh api -X PUT "repos/${REPO}/branches/main/protection" --input - <<JSON
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Pruebas y cobertura",
      "SonarCloud (Quality Gate)",
      "Validar manifiestos Kubernetes",
      "Auditoría de cumplimiento",
      "Imagen Docker"
    ]
  },
  "enforce_admins": ${ENFORCE_ADMINS},
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true
  },
  "required_conversation_resolution": true,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON

echo "✅ Protección aplicada a main en ${REPO}:"
gh api "repos/${REPO}/branches/main/protection" \
  --jq '{checks: .required_status_checks.contexts, strict: .required_status_checks.strict, enforce_admins: .enforce_admins.enabled, force_push: .allow_force_pushes.enabled}'
