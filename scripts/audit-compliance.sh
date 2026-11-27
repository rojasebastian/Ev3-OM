#!/usr/bin/env bash
# ============================================================
# scripts/audit-compliance.sh (EV3 - IE5 / IE6)
# Auditoría automatizada de políticas de seguridad y calidad ("policy as code").
# Se ejecuta en el job "compliance" del pipeline: si una política se incumple,
# el script termina con código 1 y el pipeline se detiene antes de construir
# o desplegar nada.
#
# Genera audit-report.md (se publica como artefacto: evidencia de auditoría).
# Uso: bash scripts/audit-compliance.sh
# ============================================================
set -uo pipefail
cd "$(dirname "$0")/.."

REPORT="${AUDIT_REPORT:-audit-report.md}"
# Valores de ejemplo permitidos en archivos de configuración
ALLOWED_PLACEHOLDERS='CAMBIAR|cleanup-only|admin-password|grafana-admin'
FAILS=0
TOTAL=0
ROWS=""

check() {  # check <id> <política> <función>
  local id="$1" policy="$2" fn="$3"
  TOTAL=$((TOTAL + 1))
  if "$fn" >/tmp/audit-detail.txt 2>&1; then
    printf '  ✔ %-6s %s\n' "$id" "$policy"
    ROWS+="| $id | $policy | ✅ Cumple |"$'\n'
  else
    FAILS=$((FAILS + 1))
    printf '  ✘ %-6s %s\n' "$id" "$policy" >&2
    sed 's/^/        /' /tmp/audit-detail.txt >&2
    ROWS+="| $id | $policy | ❌ **Incumple** |"$'\n'
  fi
}

# ---------------- Contenedor ----------------
p_docker_nonroot() {
  grep -Eq '^USER +[0-9]+' Dockerfile && ! grep -Eq '^USER +(0|root)\b' Dockerfile \
    || { echo "El Dockerfile debe terminar con USER numérico distinto de root"; return 1; }
}
p_docker_pinned() {
  awk 'tolower($1)=="from" { img=$2
         if (img != "scratch" && !(img in stages) && img !~ /[:@]/) { print "FROM sin etiqueta: " img; bad=1 }
         if (img ~ /:latest$/) { print "FROM usa :latest: " img; bad=1 }
         for (i=1;i<=NF;i++) if (tolower($i)=="as") stages[$(i+1)]=1 }
       END { exit bad }' Dockerfile
}
p_docker_healthcheck() { grep -q '^HEALTHCHECK' Dockerfile || { echo "Falta HEALTHCHECK"; return 1; }; }

# ---------------- Kubernetes ----------------
p_k8s_hardening() {
  local f=k8s/deployment.yaml ok=0 pattern
  for pattern in 'runAsNonRoot: true' 'readOnlyRootFilesystem: true' 'allowPrivilegeEscalation: false' \
                 'readinessProbe:' 'livenessProbe:' 'limits:' 'requests:'; do
    grep -q "$pattern" "$f" || { echo "$f no define: $pattern"; ok=1; }
  done
  return $ok
}
p_k8s_no_latest() {
  ! grep -rnE 'image:.*:latest' k8s/ observability/ 2>/dev/null | grep -v '^Binary'
}

# ---------------- Secretos ----------------
p_no_secrets() {
  ! grep -rInEi \
      --exclude-dir=.git --exclude-dir=target --exclude-dir=node_modules --exclude-dir=test \
      --exclude='*.md' --exclude='*.example*' --exclude='*.json' --exclude='audit-compliance.sh' --exclude='demo-falla.sh' \
      -e "(password|passwd|secret|token|api[_-]?key)[A-Za-z_]*[\"']?[[:space:]]*[:=][[:space:]]*[\"']?[A-Za-z0-9/+_.-]{8,}" . \
    | grep -Ev ':[0-9]+:[[:space:]]*(#|//)' \
    | grep -Eiv "$ALLOWED_PLACEHOLDERS" \
    | sed 's/^/Posible credencial en texto plano: /'
}
p_env_not_tracked() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [ -z "$(git ls-files .env)" ] || { echo ".env está versionado"; return 1; }
  fi
  grep -qE '^\.env$' .gitignore || { echo ".gitignore no excluye .env"; return 1; }
}

# ---------------- Política de calidad (anti-manipulación) ----------------
p_coverage_threshold() {
  local v
  v="$(sed -n 's:.*<jacoco.line.minimum>\(.*\)</jacoco.line.minimum>.*:\1:p' pom.xml | head -1)"
  [ -n "$v" ] && awk -v v="$v" 'BEGIN { exit !(v + 0 >= 0.75) }' \
    || { echo "El umbral de cobertura en pom.xml es '${v:-ausente}' y debe ser >= 0.75"; return 1; }
}
p_sonar_gate_blocking() {
  grep -q 'sonar.qualitygate.wait=true' .github/workflows/ci-cd.yml sonar-project.properties \
    || { echo "El Quality Gate de SonarCloud debe ser bloqueante"; return 1; }
}

# ---------------- Pipeline ----------------
p_workflow_permissions() {
  grep -Eq '^permissions:' .github/workflows/ci-cd.yml || { echo "Falta 'permissions:' global"; return 1; }
  ! grep -rq 'pull_request_target' .github/workflows || { echo "pull_request_target no está permitido"; return 1; }
}
p_trivy_pinned() {
  grep -Eq 'aquasecurity/trivy-action@[0-9a-f]{40}' .github/workflows/ci-cd.yml \
    || { echo "trivy-action debe fijarse por SHA completo"; return 1; }
}
p_dependabot() { [ -f .github/dependabot.yml ] || { echo "Falta dependabot.yml"; return 1; }; }

# ---------------- Observabilidad ----------------
p_obs_files() {
  local ok=0 f
  for f in observability/manifests/servicemonitor.yaml observability/manifests/prometheusrule.yaml \
           observability/manifests/order-manager-dashboard.json observability/install-monitoring.sh; do
    [ -f "$f" ] || { echo "Falta $f"; ok=1; }
  done
  return $ok
}
p_obs_scrape_path() {
  grep -q '/actuator/prometheus' observability/manifests/servicemonitor.yaml \
    && grep -q 'micrometer-registry-prometheus' pom.xml \
    || { echo "La API debe exponer /actuator/prometheus y el ServiceMonitor debe apuntar ahí"; return 1; }
}
p_obs_alerts() {
  local n
  n="$(grep -c 'alert:' observability/manifests/prometheusrule.yaml)"
  [ "$n" -ge 5 ] || { echo "Se esperaban >= 5 alertas, hay $n"; return 1; }
}
p_obs_dashboard() {
  local d=observability/manifests/order-manager-dashboard.json m ok=0
  python3 -c "import json,sys; json.load(open('$d'))" || { echo "El dashboard no es JSON válido"; return 1; }
  for m in ci_deploy_duration_seconds ci_test_coverage_ratio container_cpu_usage_seconds_total \
           container_memory_working_set_bytes http_server_requests_seconds_count log_level; do
    grep -q "$m" "$d" || { echo "El dashboard no incluye la métrica $m"; ok=1; }
  done
  return $ok
}

echo "▶ Auditoría de cumplimiento"
echo "Contenedor"
check C1 "La imagen no corre como root (USER numérico)" p_docker_nonroot
check C2 "Imágenes base con versión fija (sin :latest)" p_docker_pinned
check C3 "El contenedor define HEALTHCHECK" p_docker_healthcheck
echo "Kubernetes"
check K1 "Deployment endurecido: no-root, FS de solo lectura, probes y recursos" p_k8s_hardening
check K2 "Ningún manifiesto usa imágenes :latest" p_k8s_no_latest
echo "Secretos"
check S1 "Sin credenciales en texto plano en el repositorio" p_no_secrets
check S2 "El archivo .env no se versiona" p_env_not_tracked
echo "Calidad"
check Q1 "Umbral de cobertura JaCoCo >= 75 % (no se puede debilitar)" p_coverage_threshold
check Q2 "Quality Gate de SonarCloud bloqueante" p_sonar_gate_blocking
echo "Pipeline"
check P1 "Workflow con permisos mínimos y sin pull_request_target" p_workflow_permissions
check P2 "Escáner Trivy fijado por SHA (cadena de suministro)" p_trivy_pinned
check P3 "Dependabot configurado" p_dependabot
echo "Observabilidad"
check O1 "Existen ServiceMonitor, reglas, dashboard e instalador" p_obs_files
check O2 "La API expone /actuator/prometheus y se scrapea" p_obs_scrape_path
check O3 "Hay al menos 5 alertas definidas" p_obs_alerts
check O4 "El dashboard incluye las métricas clave (despliegue, cobertura, CPU, memoria, errores)" p_obs_dashboard

{
  echo "# Reporte de auditoría de cumplimiento"
  echo
  echo "- Fecha: $(date -u +'%Y-%m-%d %H:%M UTC')"
  echo "- Commit: ${GITHUB_SHA:-local}"
  echo "- Resultado: **$((TOTAL - FAILS)) de $TOTAL políticas cumplidas**"
  echo
  echo "| ID | Política | Estado |"
  echo "|---|---|---|"
  printf '%s' "$ROWS"
} > "$REPORT"

if [ "$FAILS" -gt 0 ]; then
  echo "❌ Auditoría fallida: $FAILS política(s) incumplida(s). El pipeline se detiene." >&2
  exit 1
fi
echo "✅ Auditoría aprobada: $TOTAL/$TOTAL políticas cumplidas ($REPORT)"
