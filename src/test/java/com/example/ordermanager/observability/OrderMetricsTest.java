package com.example.ordermanager.observability;

import com.example.ordermanager.model.OrderStatus;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

@DisplayName("OrderMetrics - Pruebas unitarias")
class OrderMetricsTest {

    private final SimpleMeterRegistry registry = new SimpleMeterRegistry();
    private final OrderMetrics metrics = new OrderMetrics(registry);

    @Test
    @DisplayName("orderCreated suma 1 al contador de pedidos creados")
    void shouldCountCreated() {
        metrics.orderCreated();
        assertEquals(1.0, registry.get("orders.created").counter().count());
    }

    @Test
    @DisplayName("statusChanged separa el conteo por estado")
    void shouldCountByStatus() {
        metrics.statusChanged(OrderStatus.SHIPPED);
        metrics.statusChanged(OrderStatus.SHIPPED);
        metrics.statusChanged(OrderStatus.CANCELLED);

        assertEquals(2.0, registry.get("orders.status.changed").tag("status", "SHIPPED").counter().count());
        assertEquals(1.0, registry.get("orders.status.changed").tag("status", "CANCELLED").counter().count());
    }

    @Test
    @DisplayName("invalidTransition suma 1 al contador de rechazos")
    void shouldCountInvalidTransitions() {
        metrics.invalidTransition();
        assertEquals(1.0, registry.get("orders.invalid.transition").counter().count());
    }
}
