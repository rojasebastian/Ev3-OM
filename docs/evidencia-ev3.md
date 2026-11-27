# Lista de evidencias para la entrega (EV3)

Capturas y enlaces a incluir en el README o el informe. Cada ítem está ligado a un indicador de la pauta.

| IE | Qué demostrar | Evidencia sugerida |
|---|---|---|
| **IE1** (20 %) | Monitoreo funcionando | Prometheus *Status › Targets* con `order-manager` en **UP**; Grafana *Explore* con una consulta de logs; panel de disponibilidad |
| **IE2** (20 %) | Despliegue orquestado en la nube | `kubectl get nodes,pods -A` desde la instancia EC2 (con la IP visible en la consola de AWS); job `deploy-k8s` en verde; `kubectl get servicemonitor,prometheusrule -n monitoring` |
| **IE3** (10 %) | Dashboard con métricas clave | Dashboard completo: tiempo de despliegue, cobertura, CPU/memoria, errores y logs |
| **IE4** (10 %) | Documentación | `docs/observabilidad.md` (completar sección 4 con ejemplos reales) |
| **IE5** (20 %) | Políticas de cumplimiento | Artefacto `reporte-auditoria` (16/16); Quality Gate de SonarCloud; regla de protección de `main` (captura de *Settings › Branches* o salida de `setup-branch-protection.sh`) |
| **IE6** (20 %) | El pipeline se detiene | PR de una rama `demo/falla-*` con el pipeline en **rojo** y `build`/`deploy*` omitidos; repetir con 2 tipos de falla (seguridad y calidad) |

## Secuencia recomendada para IE6
```bash
bash scripts/demo-falla.sh secreto        # seguridad → falla 'Auditoría de cumplimiento'
bash scripts/demo-falla.sh test-fallido   # calidad  → falla 'Pruebas y cobertura'
```
Abrir un PR de cada rama hacia `main`, capturar la pestaña *Checks*, y borrar las ramas al terminar.

## Pendientes del equipo
- [ ] Completar la sección ✍️ de `docs/observabilidad.md` con observaciones propias.
- [ ] Actualizar en el README los números de pruebas/cobertura con la ejecución final (ahora hay pruebas nuevas).
- [ ] Declarar en el README el uso de IA de esta evaluación.
- [ ] Escribir cada integrante su reflexión de EV3, **sin apoyo de IA** (exigido por la pauta).
- [ ] Subir a AVA y enviar por correo el enlace del repositorio.
