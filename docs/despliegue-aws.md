# Despliegue en Kubernetes sobre AWS (EV3 — IE2)

Order Manager se despliega en un clúster **k3s** (Kubernetes ligero y certificado) instalado en **una instancia EC2**.
Es lo más simple y barato para una cuenta de estudiante: no requiere EKS (≈ US$0,10/h solo por el plano de control, más nodos).

## Opciones evaluadas

| Opción | Ventajas | Inconvenientes |
|---|---|---|
| **k3s en EC2 (elegida)** | Barato, rápido, es Kubernetes real, funciona con cuenta de estudiante | Un solo nodo; tú mantienes la instancia |
| EKS | Servicio gestionado | Costo del plano de control; en AWS Academy puede estar restringido; credenciales temporales difíciles de usar desde GitHub Actions |
| GKE Autopilot | Muy simple | Pide tarjeta de crédito (crédito de prueba) |
| kind/minikube local | Gratis | No es "en la nube": solo como respaldo si el docente lo acepta |

## Requisitos
- Cuenta AWS (Academy Learner Lab o cuenta normal), región `us-east-1`.
- Repositorio en GitHub con el pipeline funcionando (SonarCloud ya configurado de la EV2).

## Paso 1 — Instancia EC2
1. **EC2 › Launch instance**: Ubuntu Server 24.04, tipo **t3.large** (2 vCPU, 8 GB; con 4 GB la pila de monitoreo queda justa), disco 30 GB.
2. Key pair: la del laboratorio (`vockey`) o una propia.
3. **Security Group** (reglas de entrada):

   | Puerto | Origen | Para qué |
   |---|---|---|
   | 22 | Mi IP | SSH |
   | 6443 | 0.0.0.0/0 | API de Kubernetes (GitHub Actions no tiene IP fija; el acceso exige el certificado cliente del kubeconfig) |
   | 30300 | Mi IP | Grafana |
4. **Elastic IP**: asignarla a la instancia (así la IP no cambia al detener/iniciar el laboratorio).

> Costo aproximado de t3.large: ~US$0,08/hora (verifica la tarifa vigente). **Detén la instancia** cuando no la uses.
> k3s arranca solo al iniciar y todo vuelve a levantarse; la Elastic IP evita invalidar el kubeconfig.

## Paso 2 — Clúster
```bash
ssh -i <llave>.pem ubuntu@<ELASTIC_IP>
git clone https://github.com/<usuario>/order-manager-eva02.git && cd order-manager-eva02
export PUBLIC_IP=<ELASTIC_IP>
bash infra/aws/bootstrap-k3s.sh
```
Al final imprime un texto largo en base64: es el valor del secret `KUBE_CONFIG_B64`. Cópialo completo.

## Paso 3 — Observabilidad
En la misma instancia:
```bash
bash observability/install-monitoring.sh
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d; echo
helm list -n monitoring        # anota las versiones instaladas en el README
```
Instala Prometheus, Grafana, Loki/Promtail y Pushgateway. Grafana queda en `http://<ELASTIC_IP>:30300` (usuario `admin`).

## Paso 4 — GitHub
1. **Settings › Environments › New environment**: `aws-k3s`. Dentro: secret **`KUBE_CONFIG_B64`**.
2. **Settings › Secrets and variables › Actions › Variables**: `K8S_DEPLOY_ENABLED` = `true`.
3. **Imagen**: en *Packages › order-manager-eva02 › Package settings*, cambia la visibilidad a **Public**
   (así el clúster descarga la imagen sin credenciales). Si debe ser privada, crea un `imagePullSecret` con un token `read:packages`.
4. *(Recomendado)* Ejecutar `bash scripts/setup-branch-protection.sh <usuario>/<repo>` desde tu máquina con `gh auth login`.

## Paso 5 — Desplegar y verificar
Haz push a `main`. El job **Despliegue en Kubernetes (nube)** aplica los manifiestos, espera el rollout, ejecuta el smoke test contra el clúster y envía las métricas al dashboard.

```bash
kubectl -n order-manager get pods,svc,hpa
kubectl -n order-manager logs deploy/order-manager --tail=20          # logs JSON con requestId
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090   # Status > Targets
```
Genera tráfico para ver datos en el dashboard:
```bash
kubectl -n order-manager port-forward svc/order-manager 8098:8098 &
bash scripts/smoke-test.sh http://localhost:8098
```

## Problemas frecuentes
| Síntoma | Causa probable |
|---|---|
| `ImagePullBackOff` | El paquete de GHCR sigue privado |
| El job falla en "Conectar con el clúster" | Puerto 6443 cerrado, o `KUBE_CONFIG_B64` con la IP equivocada |
| "Falta instalar la observabilidad" | No se ejecutó el Paso 3 |
| Paneles de CI/CD vacíos | Aún no hay un despliegue con el Pushgateway instalado; se llenan tras el siguiente push a `main` |
| Panel de logs vacío | Revisar `kubectl -n monitoring get pods` (Promtail/Loki) y que el pod use el perfil `docker` (logs JSON) |
| Pods `Pending` | Memoria insuficiente en el nodo (usar t3.large) |
