#!/usr/bin/env bash
# ============================================================
# infra/aws/bootstrap-k3s.sh (EV3 - IE2)
# Convierte UNA instancia EC2 (Ubuntu 22.04/24.04) en un clúster Kubernetes (k3s)
# listo para el despliegue. Se ejecuta DENTRO de la instancia, por SSH.
#
#   export PUBLIC_IP=<Elastic IP de la instancia>
#   bash bootstrap-k3s.sh
#
# Al final imprime el kubeconfig en base64: es el valor del secret KUBE_CONFIG_B64 en GitHub.
# k3s ya incluye metrics-server (necesario para el HPA) y almacenamiento local (PVC de PostgreSQL y Loki).
# ============================================================
set -euo pipefail
: "${PUBLIC_IP:?Define PUBLIC_IP con la IP pública (Elastic IP) de esta instancia}"

echo "▶ Instalando k3s (certificado válido para ${PUBLIC_IP})"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --tls-san ${PUBLIC_IP} --write-kubeconfig-mode 644" sh -

echo "▶ Esperando a que el nodo esté Ready"
until sudo k3s kubectl get nodes 2>/dev/null | grep -q ' Ready'; do sleep 3; done

echo "▶ Instalando Helm"
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

mkdir -p "$HOME/.kube"
cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc"

echo
echo "✅ Clúster listo. Valor del secret KUBE_CONFIG_B64 (cópialo completo):"
echo "------------------------------------------------------------"
sed "s/127.0.0.1/${PUBLIC_IP}/" /etc/rancher/k3s/k3s.yaml | base64 -w0
echo
echo "------------------------------------------------------------"
echo "Siguiente paso:  git clone <tu repo> && bash order-manager-eva02/observability/install-monitoring.sh"
