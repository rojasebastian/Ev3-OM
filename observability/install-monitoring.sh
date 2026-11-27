#!/usr/bin/env bash
# ============================================================
# observability/install-monitoring.sh (EV3 - IE1/IE2)
# Instala la pila de observabilidad en el clúster al que apunte kubectl:
#   Prometheus + Grafana (kube-prometheus-stack), Loki + Promtail y Pushgateway.
# Luego aplica ServiceMonitor, alertas y dashboard de Order Manager.
#
# Requiere: kubectl y helm apuntando al clúster. Es idempotente (se puede repetir).
# Uso:  bash observability/install-monitoring.sh
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

echo "▶ Repositorios Helm"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update >/dev/null

echo "▶ Namespace y credenciales de Grafana"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  kubectl -n monitoring create secret generic grafana-admin \
    --from-literal=admin-user=admin \
    --from-literal=admin-password="$(openssl rand -hex 12)"
fi

echo "▶ kube-prometheus-stack (Prometheus + Grafana)"
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f helm-values/kube-prometheus-stack.yaml --wait --timeout 10m

echo "▶ Loki + Promtail (logs)"
helm upgrade --install loki grafana/loki-stack \
  -n monitoring -f helm-values/loki-stack.yaml --wait --timeout 5m

echo "▶ Pushgateway (métricas del pipeline)"
helm upgrade --install pushgateway prometheus-community/prometheus-pushgateway \
  -n monitoring -f helm-values/pushgateway.yaml --wait --timeout 3m

echo "▶ Configuración de Order Manager (ServiceMonitor, alertas, dashboard)"
kubectl apply -k manifests/

echo
echo "✅ Observabilidad instalada."
echo "   Usuario Grafana: admin"
echo "   Contraseña:      kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo"
echo "   Acceso:          http://<IP_PUBLICA>:30300   (o: kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80)"
echo "   Versiones usadas (anótalas en el README para reproducibilidad): helm list -n monitoring"
