import 'package:flutter/material.dart';

/// Determina el estado de pago de un pedido
class EstadoPagoHelper {
  static const String PAGADO = 'PAGADO';
  static const String PENDIENTE_PAGO = 'PENDIENTE_PAGO';
  static const String PARCIAL = 'PARCIAL';
  static const String NO_APLICA = 'NO_APLICA';
  
  /// Determina el estado de pago basado en los datos del pedido
  static String determinarEstadoPago(Map<String, dynamic> pedido) {
    // Si ya tiene estado de pago explícito, usarlo
    final estadoPagoExplicito = pedido['estadoPago']?.toString().toUpperCase();
    if (estadoPagoExplicito != null && estadoPagoExplicito.isNotEmpty) {
      return estadoPagoExplicito;
    }
    
    // Inferir del monto pagado
    final total = (pedido['total'] ?? 0).toDouble();
    final montoPagado = (pedido['montoPagado'] ?? 0).toDouble();
    
    if (montoPagado >= total && total > 0) {
      return PAGADO;
    }
    
    if (montoPagado > 0 && montoPagado < total) {
      return PARCIAL;
    }
    
    // Inferir de evidencias de pago (compatibilidad hacia atrás)
    final evidencias = pedido['evidencias'] as List? ?? [];
    if (evidencias.isNotEmpty) {
      return PAGADO; // Asumimos pagado si tiene comprobantes
    }
    
    return PENDIENTE_PAGO;
  }
  
  /// Calcula días sin pago desde que se completó el pedido
  static int calcularDiasSinPago(Map<String, dynamic> pedido) {
    final estadoPago = determinarEstadoPago(pedido);
    if (estadoPago == PAGADO) return 0;
    
    // Usar fechaCompletado si existe, sino fecha del pedido
    String? fechaStr = pedido['fechaCompletado']?.toString() ?? pedido['fecha']?.toString();
    if (fechaStr == null || fechaStr.isEmpty) return 0;
    
    try {
      // Intentar parsear varios formatos de fecha
      DateTime fechaCompletado;
      if (fechaStr.contains('T')) {
        fechaCompletado = DateTime.parse(fechaStr);
      } else if (fechaStr.contains('/')) {
        final partes = fechaStr.split('/');
        if (partes.length == 3) {
          fechaCompletado = DateTime(
            int.parse(partes[2]),
            int.parse(partes[1]),
            int.parse(partes[0]),
          );
        } else {
          return 0;
        }
      } else {
        return 0;
      }
      
      return DateTime.now().difference(fechaCompletado).inDays;
    } catch (e) {
      return 0;
    }
  }
  
  /// Obtiene el color de alerta según días sin pago
  static Color getColorAlerta(int diasSinPago) {
    if (diasSinPago <= 2) return Colors.amber.shade600;
    if (diasSinPago <= 5) return Colors.orange.shade600;
    return Colors.red.shade600;
  }
  
  /// Obtiene el texto de alerta
  static String getTextoAlerta(int diasSinPago) {
    if (diasSinPago == 0) return 'Hoy';
    if (diasSinPago == 1) return '1 día';
    return '$diasSinPago días';
  }
  
  /// Obtiene el color del estado de pago
  static Color getColorEstadoPago(String estadoPago) {
    switch (estadoPago) {
      case PAGADO: return Colors.green;
      case PARCIAL: return Colors.amber.shade700;
      case PENDIENTE_PAGO: return Colors.red.shade400;
      case NO_APLICA: return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  /// Obtiene el ícono del estado de pago
  static IconData getIconoEstadoPago(String estadoPago) {
    switch (estadoPago) {
      case PAGADO: return Icons.check_circle;
      case PARCIAL: return Icons.pie_chart;
      case PENDIENTE_PAGO: return Icons.warning_amber_rounded;
      case NO_APLICA: return Icons.block;
      default: return Icons.help_outline;
    }
  }
}
