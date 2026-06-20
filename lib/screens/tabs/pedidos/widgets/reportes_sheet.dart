import 'package:flutter/material.dart';
import '../helpers/estado_pago_helper.dart';
import '../models/reporte_mensual.dart';

/// Bottom sheet para mostrar reportes de ventas mensuales
class ReportesSheet extends StatefulWidget {
  final List<Map<String, dynamic>> pedidos;

  const ReportesSheet({super.key, required this.pedidos});

  @override
  State<ReportesSheet> createState() => _ReportesSheetState();
}

class _ReportesSheetState extends State<ReportesSheet> {
  int _mesSeleccionado = DateTime.now().month;
  int _anioSeleccionado = DateTime.now().year;

  List<ReporteMensual> get _reportesMensuales {
    final Map<String, ReporteMensual> reportes = {};
    
    for (var pedido in widget.pedidos) {
      final estado = (pedido['estado'] ?? '').toString().toUpperCase();
      if (estado != 'COMPLETADO') continue;
      
      // Parsear fecha
      String? fechaStr = pedido['fecha']?.toString();
      if (fechaStr == null || fechaStr.isEmpty) continue;
      
      int mes, anio;
      try {
        if (fechaStr.contains('/')) {
          final partes = fechaStr.split('/');
          if (partes.length >= 3) {
            mes = int.parse(partes[1]);
            anio = int.parse(partes[2]);
            if (anio < 100) anio += 2000;
          } else {
            continue;
          }
        } else if (fechaStr.contains('T')) {
          final dt = DateTime.parse(fechaStr);
          mes = dt.month;
          anio = dt.year;
        } else {
          continue;
        }
      } catch (e) {
        continue;
      }
      
      final key = '$anio-$mes';
      final total = (pedido['total'] ?? 0).toDouble();
      final estadoPago = EstadoPagoHelper.determinarEstadoPago(pedido);
      final montoPagado = estadoPago == EstadoPagoHelper.PAGADO 
          ? total 
          : (pedido['montoPagado'] ?? 0).toDouble();
      
      if (reportes.containsKey(key)) {
        final r = reportes[key]!;
        reportes[key] = ReporteMensual(
          mes: mes,
          anio: anio,
          totalVendido: r.totalVendido + total,
          totalCobrado: r.totalCobrado + montoPagado,
          totalPendiente: r.totalPendiente + (total - montoPagado),
          cantidadPedidos: r.cantidadPedidos + 1,
          pedidosPagados: r.pedidosPagados + (estadoPago == EstadoPagoHelper.PAGADO ? 1 : 0),
          pedidosPendientes: r.pedidosPendientes + (estadoPago != EstadoPagoHelper.PAGADO ? 1 : 0),
        );
      } else {
        reportes[key] = ReporteMensual(
          mes: mes,
          anio: anio,
          totalVendido: total,
          totalCobrado: montoPagado,
          totalPendiente: total - montoPagado,
          cantidadPedidos: 1,
          pedidosPagados: estadoPago == EstadoPagoHelper.PAGADO ? 1 : 0,
          pedidosPendientes: estadoPago != EstadoPagoHelper.PAGADO ? 1 : 0,
        );
      }
    }
    
    // Ordenar por fecha descendente
    final lista = reportes.values.toList();
    lista.sort((a, b) {
      final cmpAnio = b.anio.compareTo(a.anio);
      if (cmpAnio != 0) return cmpAnio;
      return b.mes.compareTo(a.mes);
    });
    
    return lista;
  }

  ReporteMensual? get _reporteSeleccionado {
    try {
      return _reportesMensuales.firstWhere(
        (r) => r.mes == _mesSeleccionado && r.anio == _anioSeleccionado,
      );
    } catch (e) {
      return null;
    }
  }

  // Totales generales
  Map<String, dynamic> get _totalesGenerales {
    double totalVendido = 0;
    double totalCobrado = 0;
    int pedidos = 0;
    
    for (var r in _reportesMensuales) {
      totalVendido += r.totalVendido;
      totalCobrado += r.totalCobrado;
      pedidos += r.cantidadPedidos;
    }
    
    return {
      'totalVendido': totalVendido,
      'totalCobrado': totalCobrado,
      'totalPendiente': totalVendido - totalCobrado,
      'pedidos': pedidos,
    };
  }

  @override
  Widget build(BuildContext context) {
    final reportes = _reportesMensuales;
    final totales = _totalesGenerales;
    final reporteActual = _reporteSeleccionado;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.bar_chart_rounded, color: Colors.indigo.shade600, size: 24),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reportes de Ventas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text('Resumen financiero', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          
          // Totales Generales
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade600, Colors.blue.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('TOTAL HISTÓRICO', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('S/ ${totales['totalVendido'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              const Text('Cobrado', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          Text('S/ ${totales['totalCobrado'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white24),
                    Expanded(
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: Colors.red.shade300, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              const Text('Por cobrar', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          Text('S/ ${totales['totalPendiente'].toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Lista de meses
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('Por Mes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${reportes.length} meses', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ],
            ),
          ),
          
          const SizedBox(height: 8),
          
          Expanded(
            child: reportes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Sin datos aún', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: reportes.length,
                    itemBuilder: (context, index) {
                      final r = reportes[index];
                      final isSelected = r.mes == _mesSeleccionado && r.anio == _anioSeleccionado;
                      
                      return GestureDetector(
                        onTap: () => setState(() {
                          _mesSeleccionado = r.mes;
                          _anioSeleccionado = r.anio;
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.indigo.shade50 : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? Colors.indigo.shade300 : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.indigo.shade100 : Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    r.nombreMes.substring(0, 3),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.indigo.shade700 : Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.nombreMes, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text('${r.cantidadPedidos} pedidos', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('S/ ${r.totalVendido.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Row(
                                    children: [
                                      if (r.totalPendiente > 0) ...[
                                        Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red.shade400),
                                        const SizedBox(width: 4),
                                        Text('S/ ${r.totalPendiente.toStringAsFixed(0)} pendiente', style: TextStyle(fontSize: 11, color: Colors.red.shade400)),
                                      ] else ...[
                                        Icon(Icons.check_circle, size: 14, color: Colors.green.shade400),
                                        const SizedBox(width: 4),
                                        Text('Todo cobrado', style: TextStyle(fontSize: 11, color: Colors.green.shade400)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          // Detalle del mes seleccionado
          if (reporteActual != null)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  Text('Detalle ${reporteActual.nombreMes}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetalleItem('Vendido', reporteActual.totalVendido, Colors.indigo),
                      ),
                      Expanded(
                        child: _buildDetalleItem('Cobrado', reporteActual.totalCobrado, Colors.green),
                      ),
                      Expanded(
                        child: _buildDetalleItem('Pendiente', reporteActual.totalPendiente, Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Barra de progreso
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: reporteActual.porcentajeCobrado / 100,
                      backgroundColor: Colors.red.shade100,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade400),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reporteActual.porcentajeCobrado.toStringAsFixed(1)}% cobrado',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetalleItem(String label, double valor, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text('S/ ${valor.toStringAsFixed(2)}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
