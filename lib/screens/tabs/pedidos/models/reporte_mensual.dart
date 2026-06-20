/// Modelo de reporte mensual de ventas
class ReporteMensual {
  final int mes;
  final int anio;
  final double totalVendido;
  final double totalCobrado;
  final double totalPendiente;
  final int cantidadPedidos;
  final int pedidosPagados;
  final int pedidosPendientes;
  
  ReporteMensual({
    required this.mes,
    required this.anio,
    required this.totalVendido,
    required this.totalCobrado,
    required this.totalPendiente,
    required this.cantidadPedidos,
    required this.pedidosPagados,
    required this.pedidosPendientes,
  });
  
  String get nombreMes {
    const meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    return '${meses[mes - 1]} $anio';
  }
  
  double get porcentajeCobrado => totalVendido > 0 ? (totalCobrado / totalVendido) * 100 : 0;
}
