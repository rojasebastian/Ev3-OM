package com.example.ordermanager.service;

import com.example.ordermanager.dto.AddItemRequest;
import com.example.ordermanager.dto.CreateOrderRequest;
import com.example.ordermanager.exception.InvalidOrderStateException;
import com.example.ordermanager.exception.OrderNotFoundException;
import com.example.ordermanager.model.Order;
import com.example.ordermanager.model.OrderItem;
import com.example.ordermanager.model.OrderStatus;
import com.example.ordermanager.observability.OrderMetrics;
import com.example.ordermanager.repository.OrderRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    private final OrderRepository repository;
    private final OrderMetrics metrics;

    public OrderService(OrderRepository repository, OrderMetrics metrics) {
        this.repository = repository;
        this.metrics = metrics;
    }

    // ============================================================
    // CONSULTAS
    // ============================================================

    public List<Order> getAllOrders() {
        return repository.findAll();
    }

    public List<Order> getOrdersByStatus(OrderStatus status) {
        return repository.findByStatus(status);
    }

    public Order getOrderById(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new OrderNotFoundException(id));
    }

    // ============================================================
    // CREACIÓN
    // ============================================================

    @Transactional
    public Order createOrder(CreateOrderRequest request) {
        Order order = new Order(request.getCustomerName());

        if (request.getItems() != null) {
            for (AddItemRequest itemReq : request.getItems()) {
                order.addItem(new OrderItem(
                        itemReq.getProductName(),
                        itemReq.getQuantity(),
                        itemReq.getUnitPrice()
                ));
            }
        }
        Order saved = repository.save(order);
        metrics.orderCreated();
        log.info("Pedido {} creado", saved.getId());
        return saved;
    }

    // ============================================================
    // MODIFICACIÓN
    // ============================================================

    @Transactional
    public Order addItem(Long orderId, AddItemRequest request) {
        Order order = getOrderById(orderId);

        if (!order.canBeModified()) {
            metrics.invalidTransition();
            log.warn("Pedido {}: no se puede modificar en estado {}", orderId, order.getStatus());
            throw new InvalidOrderStateException(
                    "Solo se pueden modificar pedidos en estado PENDING. Actual: " + order.getStatus()
            );
        }

        OrderItem item = new OrderItem(
                request.getProductName(),
                request.getQuantity(),
                request.getUnitPrice()
        );
        order.addItem(item);
        return repository.save(order);
    }

    // ============================================================
    // TRANSICIONES
    // ============================================================

    @Transactional
    public Order confirmOrder(Long id) {
        return transitionTo(id, OrderStatus.PENDING, OrderStatus.CONFIRMED);
    }

    @Transactional
    public Order shipOrder(Long id) {
        return transitionTo(id, OrderStatus.CONFIRMED, OrderStatus.SHIPPED);
    }

    @Transactional
    public Order deliverOrder(Long id) {
        return transitionTo(id, OrderStatus.SHIPPED, OrderStatus.DELIVERED);
    }

    @Transactional
    public Order cancelOrder(Long id) {
        Order order = getOrderById(id);

        if (order.getStatus() == OrderStatus.DELIVERED) {
            metrics.invalidTransition();
            log.warn("Pedido {}: cancelación rechazada, ya fue entregado", id);
            throw new InvalidOrderStateException(
                    "Un pedido entregado no puede cancelarse"
            );
        }
        if (order.getStatus() == OrderStatus.CANCELLED) {
            metrics.invalidTransition();
            log.warn("Pedido {}: cancelación rechazada, ya estaba cancelado", id);
            throw new InvalidOrderStateException("El pedido ya está cancelado");
        }

        order.setStatus(OrderStatus.CANCELLED);
        Order saved = repository.save(order);
        metrics.statusChanged(OrderStatus.CANCELLED);
        log.info("Pedido {} cancelado", id);
        return saved;
    }

    // ============================================================
    // AUXILIAR
    // ============================================================

    private Order transitionTo(Long id, OrderStatus expected, OrderStatus target) {
        Order order = getOrderById(id);

        if (order.getStatus() != expected) {
            metrics.invalidTransition();
            log.warn("Pedido {}: transición inválida {} -> {}", id, order.getStatus(), target);
            throw new InvalidOrderStateException(
                    order.getStatus().name(),
                    target.name()
            );
        }

        order.setStatus(target);
        Order saved = repository.save(order);
        metrics.statusChanged(target);
        log.info("Pedido {} -> {}", id, target);
        return saved;
    }

    // ============================================================
    // ELIMINACIÓN
    // ============================================================

    @Transactional
    public void deleteOrder(Long id) {
        if (!repository.existsById(id)) {
            throw new OrderNotFoundException(id);
        }
        repository.deleteById(id);
    }
}
