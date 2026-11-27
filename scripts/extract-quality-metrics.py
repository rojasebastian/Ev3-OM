#!/usr/bin/env python3
"""
scripts/extract-quality-metrics.py (EV3 - IE3)

Lee los reportes que deja 'mvn verify' y escribe en la salida estándar líneas
clave=valor listas para $GITHUB_OUTPUT:

    coverage=0.9672     (cobertura de líneas de JaCoCo, entre 0 y 1)
    tests=69            (pruebas ejecutadas)
    failures=0          (fallos + errores)

Uso:  python3 scripts/extract-quality-metrics.py >> "$GITHUB_OUTPUT"
"""
import glob
import sys
import xml.etree.ElementTree as ET


def line_coverage(path="target/site/jacoco/jacoco.xml"):
    root = ET.parse(path).getroot()
    # Los contadores globales son hijos directos de <report>
    for counter in root.findall("counter"):
        if counter.get("type") == "LINE":
            missed, covered = int(counter.get("missed")), int(counter.get("covered"))
            total = missed + covered
            return covered / total if total else 0.0
    raise ValueError("jacoco.xml no tiene el contador LINE")


def test_totals(pattern="target/surefire-reports/TEST-*.xml"):
    tests = failures = 0
    files = glob.glob(pattern)
    if not files:
        raise FileNotFoundError("no hay reportes de Surefire")
    for report in files:
        suite = ET.parse(report).getroot()
        tests += int(suite.get("tests", 0))
        failures += int(suite.get("failures", 0)) + int(suite.get("errors", 0))
    return tests, failures


if __name__ == "__main__":
    try:
        coverage = line_coverage()
        tests, failures = test_totals()
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"No se pudieron leer los reportes: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"coverage={coverage:.4f}")
    print(f"tests={tests}")
    print(f"failures={failures}")
