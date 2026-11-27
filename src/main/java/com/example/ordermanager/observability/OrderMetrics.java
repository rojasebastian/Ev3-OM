package com.example.ordermanager.observability;

import com.example.ordermanager.model.OrderStatus;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Component;

/**
 * Métricas de negocio del microservicio (EV3 - IE1/IE3).
 *
 * Se publican en /actuator/prometheus como:
 *   orders_created_total
 *   orders_status_changed_total{status="CONFIRMED|SHIPPED|DELIVERED|CANCELLED"}
 *   orders_invalid_transition_total
 *
 * Complementan las métricas técnicas automáticas (http_server_requests_*, jvm_*).
 */
@Component
public class OrderMetrics {

    private final MeterRegistry registry;
    private final Counter created;
    private final Counter invalidTransitions;

    public OrderMetrics(MeterRegistry registry) {
        this.registry = registry;
        this.created = Counter.builder("orders.created")
                .description("Pedidos creados")
                .register(registry);
        this.invalidTransitions = Counter.builder("orders.invalid.transition")
                .description("Intentos de transición de estado rechazados por las reglas de negocio")
                .register(registry);
    }

    public void orderCreated() {
        created.increment();
    }

    public void statusChanged(OrderStatus newStatus) {
        registry.counter("orders.status.changed", "status", newStatus.name()).increment();
    }

    public void invalidTransition() {
        invalidTransitions.increment();
    }
}
