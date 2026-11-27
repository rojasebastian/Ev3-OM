#!/usr/bin/env bash
# ============================================================
# scripts/push-ci-metrics.sh (EV3 - IE3)
# Envía las métricas del pipeline al Pushgateway, de donde las scrapea
# Prometheus y las muestra el dashboard de Grafana.
#
# Variables requeridas:
#   PUSHGATEWAY_URL   p. ej. http://localhost:9091 (vía kubectl port-forward)
#   DEPLOY_SECONDS    duración del despliegue en segundos
#   COVERAGE          cobertura de líneas (0..1)
#   TESTS, FAILURES   pruebas ejecutadas y fallidas
#   COMMIT, RUN_ID, ACTOR
# DRY_RUN=1 imprime el contenido sin enviarlo.
# ============================================================
set -euo pipefail

: "${PUSHGATEWAY_URL:?falta PUSHGATEWAY_URL}"
: "${DEPLOY_SECONDS:?falta DEPLOY_SECONDS}"
: "${COVERAGE:?falta COVERAGE}"
: "${TESTS:?falta TESTS}"
: "${FAILURES:?falta FAILURES}"
: "${COMMIT:?falta COMMIT}"
: "${RUN_ID:?falta RUN_ID}"
: "${ACTOR:?falta ACTOR}"

payload="$(cat <<METRICS
# TYPE ci_deploy_duration_seconds gauge
ci_deploy_duration_seconds ${DEPLOY_SECONDS}
# TYPE ci_deploy_timestamp_seconds gauge
ci_deploy_timestamp_seconds $(date +%s)
# TYPE ci_test_coverage_ratio gauge
ci_test_coverage_ratio ${COVERAGE}
# TYPE ci_tests_total gauge
ci_tests_total ${TESTS}
# TYPE ci_tests_failed_total gauge
ci_tests_failed_total ${FAILURES}
# TYPE ci_deploy_info gauge
ci_deploy_info{commit="${COMMIT:0:7}",run_id="${RUN_ID}",actor="${ACTOR}"} 1
METRICS
)"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "$payload"
  exit 0
fi

# PUT reemplaza el grupo completo: siempre queda solo el último despliegue.
echo "$payload" | curl -sf --max-time 15 --data-binary @- -X PUT \
  "${PUSHGATEWAY_URL}/metrics/job/order-manager-ci/instance/github-actions"
echo "Métricas del pipeline enviadas al Pushgateway."
