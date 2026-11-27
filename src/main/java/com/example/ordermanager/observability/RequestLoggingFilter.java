package com.example.ordermanager.observability;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.servlet.HandlerMapping;

import java.io.IOException;
import java.util.List;
import java.util.UUID;

/**
 * Registro de acceso y correlación de logs (EV3 - IE1).
 *
 * - Genera un requestId por petición, lo deja en el MDC (aparece en cada línea
 *   de log de esa petición) y lo devuelve en la cabecera X-Request-Id.
 * - Escribe UNA línea de acceso por petición: método, ruta, estado y duración.
 *   El nivel sube a WARN (4xx) o ERROR (5xx) para poder filtrar errores en Loki.
 *
 * Seguridad: el requestId siempre lo genera el servidor y la ruta que se
 * registra es el patrón del controlador (p. ej. /api/orders/{id}), nunca texto
 * escrito por el cliente. Así se evita la inyección de logs.
 */
@Component
public class RequestLoggingFilter extends OncePerRequestFilter {

    public static final String REQUEST_ID_HEADER = "X-Request-Id";
    public static final String MDC_REQUEST_ID = "requestId";

    private static final Logger log = LoggerFactory.getLogger(RequestLoggingFilter.class);
    private static final List<String> KNOWN_METHODS =
            List.of("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS");

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        // Las probes de Kubernetes y el scrape de Prometheus ocurren cada pocos segundos: se omiten.
        return request.getRequestURI().startsWith("/actuator");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        MDC.put(MDC_REQUEST_ID, UUID.randomUUID().toString());
        response.setHeader(REQUEST_ID_HEADER, MDC.get(MDC_REQUEST_ID));
        long start = System.nanoTime();
        try {
            chain.doFilter(request, response);
        } finally {
            long durationMs = (System.nanoTime() - start) / 1_000_000;
            logAccess(request, response.getStatus(), durationMs);
            MDC.remove(MDC_REQUEST_ID);
        }
    }

    private void logAccess(HttpServletRequest request, int status, long durationMs) {
        String method = KNOWN_METHODS.stream()
                .filter(known -> known.equals(request.getMethod()))
                .findFirst()
                .orElse("OTHER");
        Object pattern = request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE);
        String route = pattern != null ? pattern.toString() : "sin-ruta";

        if (status >= 500) {
            log.error("HTTP {} {} -> {} ({} ms)", method, route, status, durationMs);
        } else if (status >= 400) {
            log.warn("HTTP {} {} -> {} ({} ms)", method, route, status, durationMs);
        } else {
            log.info("HTTP {} {} -> {} ({} ms)", method, route, status, durationMs);
        }
    }
}
