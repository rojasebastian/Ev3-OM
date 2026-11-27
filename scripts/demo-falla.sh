#!/usr/bin/env bash
# ============================================================
# scripts/demo-falla.sh (EV3 - IE6)
# Genera EVIDENCIA de que el pipeline se detiene ante una falla crítica.
# Crea una rama de demostración con UNA falla intencional, la sube a GitHub
# y te dice qué esperar. Nunca toca main.
#
# Uso:  bash scripts/demo-falla.sh <tipo>
#   secreto       agrega una contraseña en texto plano a un ConfigMap   (seguridad)
#   root          hace que el contenedor corra como root                (seguridad)
#   test-fallido  agrega una prueba que falla                           (calidad)
#
# Después: abrir un Pull Request de la rama hacia main, capturar el pipeline en rojo
# y los jobs build/deploy omitidos. Para limpiar: git push origin --delete <rama>
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

TYPE="${1:-}"
BRANCH="demo/falla-${TYPE}-$(date +%Y%m%d-%H%M%S)"

case "$TYPE" in
  secreto|root|test-fallido) ;;
  *) echo "Uso: $0 <secreto|root|test-fallido>" >&2; exit 2 ;;
esac

git diff --quiet && git diff --cached --quiet || { echo "Hay cambios sin commitear; guárdalos antes." >&2; exit 1; }
git checkout -b "$BRANCH"

case "$TYPE" in
  secreto)
    printf '  DB_PASSWORD: "ClaveSuperSecreta2026"\n' >> k8s/configmap.yaml
    EXPECT="job 'Auditoría de cumplimiento' (política S1: credencial en texto plano)"
    ;;
  root)
    sed -i 's/^USER 10001:10001/USER root/' Dockerfile
    EXPECT="job 'Auditoría de cumplimiento' (política C1) y luego 'Imagen Docker' (verificación de usuario)"
    ;;
  test-fallido)
    DIR=src/test/java/com/example/ordermanager
    cat > "$DIR/DemoFallaTest.java" <<'JAVA'
package com.example.ordermanager;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** Prueba que falla A PROPÓSITO para demostrar que el pipeline se detiene (EV3 - IE6). */
class DemoFallaTest {
    @Test
    void fallaIntencional() {
        assertEquals(1, 2, "Falla de calidad simulada");
    }
}
JAVA
    EXPECT="job 'Pruebas y cobertura' (mvn verify falla)"
    ;;
esac

git add -A
git commit -q -m "demo: falla critica '${TYPE}' para evidenciar el bloqueo del pipeline"
git push -u origin "$BRANCH"

echo
echo "✅ Rama $BRANCH subida."
echo "   Esperado: el pipeline FALLA en el ${EXPECT}."
echo "   Los jobs 'Imagen Docker' y 'Despliegue' NO deben ejecutarse."
echo "   Abre el Pull Request hacia main y captura la pantalla de Actions."
echo "   Limpieza:  git checkout main && git push origin --delete $BRANCH"
