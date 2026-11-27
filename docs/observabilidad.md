# Observabilidad, métricas y cumplimiento — Order Manager (EV3)

> **Borrador técnico para revisar.** Este documento describe *cómo está conectado* el sistema (hecho verificable en el código).
> Las secciones marcadas con ✍️ son decisiones y justificaciones que el equipo debe **revisar y reescribir con sus propias palabras**,
> según la pauta de IA de la evaluación.

## 1. Vista general

```
 commit / PR
     │
     ▼
┌──────────────────────── GitHub Actions ─────────────────────────┐
│ test ──► métricas (cobertura, pruebas) ─────────────┐            │
│ sonar (Quality Gate ⛔)                              │            │
│ compliance (auditoría + secretos ⛔)                 │            │
│ k8s-validate (render de manifiestos ⛔)              │            │
│        └──► build (Trivy ⛔, smoke test ⛔) ──► deploy (simulado) │
│                                       └──► deploy-k8s ──────────┼──► Pushgateway
└──────────────────────────────────────────┬──────────────────────┘          │
                                           ▼                                 ▼
                              Kubernetes (k3s en AWS EC2)             Prometheus ──► Grafana
                              ├─ order-manager (2+ réplicas)  ◄─scrape─┘  ▲            ▲
                              ├─ postgres                                 │            │
                              └─ promtail ──► Loki ───────────────────────┴────────────┘
                                                              ⛔ = detiene el pipeline si falla
```

## 2. Herramientas y dónde se integran

| Herramienta | Qué hace | Dónde está en el repo | Etapa del pipeline |
|---|---|---|---|
| **Micrometer + Actuator** | La API publica métricas técnicas (HTTP, JVM) y de negocio (`orders_*`) en `/actuator/prometheus` | `pom.xml`, `observability/OrderMetrics.java`, `application*.properties` | Se verifica en el smoke test (paso 6) |
| **Logs JSON (ECS) + `requestId`** | Cada línea de log es JSON con nivel, logger y un `requestId` que correlaciona una petición | `RequestLoggingFilter.java`, `application-docker.properties` | Runtime |
| **Prometheus** | Scrapea la API cada 15 s, evalúa alertas y guarda 3 días de métricas | `observability/helm-values/kube-prometheus-stack.yaml`, `manifests/servicemonitor.yaml` | `deploy-k8s` aplica el ServiceMonitor |
| **kube-state-metrics / cAdvisor** | CPU, memoria, reinicios y réplicas por pod | incluido en kube-prometheus-stack | Runtime |
| **Loki + Promtail** | Recolecta y consulta los logs de todos los pods | `helm-values/loki-stack.yaml` | Runtime |
| **Pushgateway** | Recibe las métricas **del pipeline** (tiempo de despliegue, cobertura, pruebas) | `scripts/push-ci-metrics.sh`, `helm-values/pushgateway.yaml` | `deploy-k8s`, último paso |
| **Grafana** | Dashboard único con métricas, CI/CD y logs | `manifests/order-manager-dashboard.json` (se carga solo por ConfigMap) | Se actualiza en cada despliegue |
| **Reglas de alerta** | 8 alertas con una "decisión" asociada | `manifests/prometheusrule.yaml` | `deploy-k8s` las aplica |
| **JaCoCo** | Cobertura de líneas; bloquea bajo 75 % | `pom.xml` | `test` |
| **SonarCloud** | Análisis estático + Quality Gate | `sonar-project.properties`, job `sonar` | `sonar` |
| **Trivy** | Vulnerabilidades HIGH/CRITICAL en la imagen y secretos en el repo | jobs `build` y `compliance` | `build`, `compliance` |
| **`audit-compliance.sh`** | 16 políticas como código (contenedor, K8s, secretos, umbrales, pipeline, observabilidad) | `scripts/audit-compliance.sh` | `compliance` |
| **Branch protection** | Impide integrar a `main` sin checks verdes | `scripts/setup-branch-protection.sh` | Configuración en GitHub |

## 3. Métricas del dashboard

| Panel | Consulta (resumen) | Qué pregunta responde |
|---|---|---|
| Pods disponibles | `sum(up{service="order-manager"})` | ¿Está arriba el servicio? |
| Errores 5xx | `rate(http_server_requests_seconds_count{status=~"5.."})` | ¿Estamos fallando? |
| Tiempo del último despliegue | `ci_deploy_duration_seconds` | ¿El despliegue se está volviendo lento? |
| Cobertura de pruebas | `ci_test_coverage_ratio` | ¿Seguimos sobre el 75 %? |
| CPU / memoria por pod | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` | ¿Los límites están bien dimensionados? |
| Latencia p95/p99 | `histogram_quantile(...)` | ¿La experiencia del usuario se degrada? |
| Errores en logs | Loki: `{app="order-manager"} \| json \| log_level="ERROR"` | ¿Qué falló exactamente? (con `requestId`) |
| Pedidos y transiciones rechazadas | `orders_created_total`, `orders_invalid_transition_total` | ¿El negocio opera con normalidad? |

## 4. ✍️ Cómo las métricas apoyan decisiones técnicas (borrador)

| Señal | Umbral | Decisión posible |
|---|---|---|
| `OrderManagerDown` | sin pods scrapeables 1 min | Revisar logs; si coincide con un despliegue reciente, `kubectl rollout undo` |
| `OrderManagerHighErrorRate` | > 5 % de 5xx durante 5 min | Buscar la excepción por `requestId` en Loki; decidir rollback o hotfix |
| `OrderManagerHighLatency` | p95 > 500 ms | Mirar CPU y pool de BD; confirmar que el HPA escala |
| `OrderManagerHighMemory` / `HighCPU` | > 85 % del límite | Ajustar `limits` y `requests` en `deployment.yaml` |
| Cobertura | < 75 % | El pipeline ya se detiene; el panel muestra la tendencia antes de llegar al límite |
| Tiempo de despliegue | > 7 min | Revisar probes, tamaño de imagen y recursos |
| Transiciones rechazadas altas | > 10 en el rango | Posible error del cliente o del flujo de negocio: revisar la integración |

*Completar con ejemplos reales observados durante las pruebas (qué vieron en el dashboard y qué decidieron).*

## 5. Políticas de cumplimiento (IE5)

| Mecanismo | Política | Se comprueba en |
|---|---|---|
| `audit-compliance.sh` C1–C3 | Imagen no-root, base con versión fija, HEALTHCHECK | job `compliance` |
| `audit-compliance.sh` K1–K2 | Deployment endurecido, sin `:latest` | job `compliance` |
| `audit-compliance.sh` S1–S2 | Sin credenciales en texto plano; `.env` no versionado | job `compliance` |
| `audit-compliance.sh` Q1–Q2 | Umbral de cobertura ≥ 75 % y Quality Gate bloqueante (no se pueden debilitar) | job `compliance` |
| `audit-compliance.sh` P1–P3 | Permisos mínimos, Trivy fijado por SHA, Dependabot | job `compliance` |
| `audit-compliance.sh` O1–O4 | La observabilidad no puede desaparecer del repositorio | job `compliance` |
| Trivy `scanners: secret` | Detección de secretos conocidos | job `compliance` |
| SonarCloud | Quality Gate | job `sonar` |
| Branch protection | `main` solo recibe PR con checks verdes | `setup-branch-protection.sh` |

El reporte `audit-report.md` se publica como artefacto `reporte-auditoria` (90 días): es la evidencia de auditoría de cada ejecución.

## 6. Detención del pipeline ante fallas críticas (IE6)

| Falla crítica | Quién la detecta | Efecto |
|---|---|---|
| Prueba fallida o cobertura < 75 % | `test` (JaCoCo) | `build` y `deploy*` no corren |
| Quality Gate de Sonar rojo | `sonar` | ídem |
| Credencial en texto plano, root, umbral debilitado | `compliance` | ídem |
| Vulnerabilidad HIGH/CRITICAL con parche | Trivy en `build` | La imagen no se publica |
| Manifiestos inválidos | `k8s-validate` | ídem |
| Despliegue o smoke test fallido | `deploy-k8s` | **Rollback automático** a la revisión anterior |
| Cualquier fallo en un `push` | `alert` | Se abre un Issue |

**Cómo demostrarlo:** `bash scripts/demo-falla.sh secreto` (o `root`, `test-fallido`) crea una rama con una falla intencional.
Abrir el PR y capturar el pipeline en rojo con `build` y `deploy` omitidos. Ver `docs/evidencia-ev3.md`.
