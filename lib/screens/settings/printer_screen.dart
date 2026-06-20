import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../providers/printer_provider.dart';

class PrinterScreen extends StatefulWidget {
  const PrinterScreen({super.key});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PrinterProvider>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('🖨️ Impresora'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          Consumer<PrinterProvider>(
            builder: (context, provider, _) {
              if (provider.isConnected) {
                return TextButton.icon(
                  onPressed: () => provider.disconnect(),
                  icon: const Icon(Icons.bluetooth_disabled, color: Colors.red),
                  label: const Text('Desconectar', style: TextStyle(color: Colors.red)),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Consumer<PrinterProvider>(
        builder: (context, printerProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Estado actual de conexión
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: printerProvider.isConnected 
                        ? Colors.green.withOpacity(0.3) 
                        : Colors.grey.withOpacity(0.3),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: printerProvider.isConnected 
                            ? Colors.green.withOpacity(0.15) 
                            : Colors.grey.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        printerProvider.isConnected ? Icons.print : Icons.print_disabled,
                        size: 40,
                        color: printerProvider.isConnected ? Colors.green : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      printerProvider.isConnected ? 'Conectada' : 'No conectada',
                      style: TextStyle(
                        color: printerProvider.isConnected ? Colors.green : Colors.grey,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (printerProvider.isConnected) ...[
                      const SizedBox(height: 8),
                      Text(
                        printerProvider.connectedDeviceName,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: printerProvider.isPrinting 
                            ? null 
                            : () => _printTest(printerProvider),
                        icon: printerProvider.isPrinting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.print),
                        label: Text(
                          printerProvider.isPrinting 
                              ? 'Imprimiendo...' 
                              : 'Imprimir prueba',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Lista de dispositivos
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Dispositivos Bluetooth',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!printerProvider.isScanning)
                    IconButton(
                      onPressed: () => printerProvider.startScan(),
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              if (printerProvider.isScanning)
                Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(color: Colors.blue.shade600),
                      const SizedBox(height: 16),
                      Text(
                        'Buscando dispositivos...',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              else if (printerProvider.devices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.bluetooth_searching,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No se encontraron dispositivos',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Asegúrate de que la impresora esté encendida y en modo de emparejamiento',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ...printerProvider.devices.map(
                  (result) => _buildDeviceItem(result, printerProvider),
                ),

              // Error
              if (printerProvider.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          printerProvider.error!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Instrucciones
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Instrucciones',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '1. Enciende la impresora térmica\n'
                      '2. Activa el Bluetooth en tu dispositivo\n'
                      '3. Busca y selecciona tu impresora\n'
                      '4. Una vez conectada, podrás imprimir desde los pedidos',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeviceItem(ScanResult result, PrinterProvider provider) {
    final device = result.device;
    final name = device.platformName.isNotEmpty 
        ? device.platformName 
        : 'Dispositivo desconocido';
    final isThisConnected = provider.isConnected && 
        provider.connectedDeviceName == device.platformName;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isThisConnected 
            ? Border.all(color: Colors.green, width: 2) 
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isThisConnected 
                  ? Colors.green.withOpacity(0.15) 
                  : Colors.blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isThisConnected ? Icons.bluetooth_connected : Icons.bluetooth,
              color: isThisConnected ? Colors.green : Colors.blue,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  device.remoteId.toString(),
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isThisConnected)
            const Icon(Icons.check_circle, color: Colors.green)
          else
            ElevatedButton(
              onPressed: provider.isConnecting 
                  ? null 
                  : () => _connectToDevice(device, provider),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: provider.isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Conectar'),
            ),
        ],
      ),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device, PrinterProvider provider) async {
    final success = await provider.connectToDevice(device);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Impresora conectada'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${provider.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _printTest(PrinterProvider provider) async {
    final success = await provider.printTest('Fincas');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success 
              ? '✅ Prueba impresa correctamente' 
              : '❌ Error: ${provider.error}'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
}
