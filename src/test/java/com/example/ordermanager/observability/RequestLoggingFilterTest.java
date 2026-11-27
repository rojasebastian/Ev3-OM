package com.example.ordermanager.observability;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("RequestLoggingFilter - Pruebas unitarias")
class RequestLoggingFilterTest {

    private final RequestLoggingFilter filter = new RequestLoggingFilter();

    @Test
    @DisplayName("agrega X-Request-Id a la respuesta y limpia el MDC al terminar")
    void shouldAddRequestIdAndCleanMdc() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/orders");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        String requestId = response.getHeader(RequestLoggingFilter.REQUEST_ID_HEADER);
        assertNotNull(requestId);
        assertEquals(36, requestId.length());               // UUID generado por el servidor
        assertNull(MDC.get(RequestLoggingFilter.MDC_REQUEST_ID));
    }

    @Test
    @DisplayName("ignora el X-Request-Id enviado por el cliente (evita inyección de logs)")
    void shouldIgnoreClientProvidedRequestId() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/orders");
        request.addHeader(RequestLoggingFilter.REQUEST_ID_HEADER, "falso\nlinea-inyectada");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertNotEquals("falso\nlinea-inyectada", response.getHeader(RequestLoggingFilter.REQUEST_ID_HEADER));
    }

    @Test
    @DisplayName("no filtra las rutas de /actuator")
    void shouldSkipActuator() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/actuator/health");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilter(request, response, new MockFilterChain());

        assertNull(response.getHeader(RequestLoggingFilter.REQUEST_ID_HEADER));
    }

    @Test
    @DisplayName("registra también respuestas 4xx y 5xx sin romper la cadena")
    void shouldHandleErrorStatuses() throws Exception {
        for (int status : new int[]{404, 500}) {
            MockHttpServletRequest request = new MockHttpServletRequest("DELETE", "/api/orders/1");
            MockHttpServletResponse response = new MockHttpServletResponse();
            MockFilterChain chain = new MockFilterChain();

            response.setStatus(status);
            filter.doFilter(request, response, chain);

            assertEquals(status, response.getStatus());
            assertNotNull(response.getHeader(RequestLoggingFilter.REQUEST_ID_HEADER));
        }
    }
}
