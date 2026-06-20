import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Servicio para comunicación con Fincas Core API
class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  
  // Business ID dinámico (se establece después del login)
  static String _businessId = '';
  static String businessName      = '';
  static String businessDireccion = '';
  static String businessCiudad    = '';

  static String get businessId => _businessId.isNotEmpty ? _businessId : AppConfig.businessId;

  static set businessId(String id) => _businessId = id;

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
  };

  // ==================== AUTENTICACIÓN / NEGOCIOS ====================

  /// Buscar negocio por número de WhatsApp
  static Future<Map<String, dynamic>> buscarNegocioPorWhatsapp(String whatsapp) async {
    try {
      // Limpiar número
      whatsapp = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/negocios/por-whatsapp/$whatsapp'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {'encontrado': false, 'mensaje': 'Error del servidor'};
      }
    } catch (e) {
      return {'encontrado': false, 'mensaje': 'Error de conexión: $e'};
    }
  }

  /// Obtener lista de negocios
  static Future<List<Map<String, dynamic>>> getNegocios() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/negocios'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // ==================== PRODUCTOS ====================

  /// Obtener todos los productos con paginación
  static Future<ApiResponse<ProductosResponse>> getProductos({
    String? estado,
    String? buscar,
    int pagina = 1,
    int limite = 20,
  }) async {
    try {
      var url = '$baseUrl/api/productos/$businessId';
      final params = <String, String>{};
      if (estado != null) params['estado'] = estado;
      if (buscar != null) params['buscar'] = buscar;
      params['pagina'] = pagina.toString();
      params['limite'] = limite.toString();
      
      if (params.isNotEmpty) {
        url += '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}';
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final productos = List<Map<String, dynamic>>.from(data['productos'] ?? []);
        return ApiResponse.success(ProductosResponse(
          productos: productos,
          total: data['total'] ?? productos.length,
          pagina: data['pagina'] ?? 1,
          totalPaginas: data['totalPaginas'] ?? 1,
          hayMas: data['hayMas'] ?? false,
        ));
      } else {
        return ApiResponse.error('Error obteniendo productos');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Buscar producto por nombre
  static Future<Map<String, dynamic>?> buscarProducto(String nombre) async {
    final result = await getProductos(buscar: nombre);
    if (result.isSuccess && result.data!.productos.isNotEmpty) {
      // Buscar coincidencia más cercana
      final nombreLower = nombre.toLowerCase();
      return result.data!.productos.firstWhere(
        (p) => (p['nombre'] as String).toLowerCase().contains(nombreLower),
        orElse: () => result.data!.productos.first,
      );
    }
    return null;
  }

  /// Buscar producto por código de barras
  static Future<ApiResponse<Map<String, dynamic>>> buscarProductoPorCodigo(String codigo) async {
    try {
      // Primero intentar endpoint específico
      final response = await http.get(
        Uri.parse('$baseUrl/api/productos/$businessId/codigo/$codigo'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['producto'] != null) {
          return ApiResponse.success(data['producto']);
        }
      }
    } catch (e) {
      // Continuar con búsqueda alternativa
    }
    
    // Fallback: buscar en la lista de productos
    try {
      final result = await getProductos(buscar: codigo, limite: 100);
      if (result.isSuccess && result.data != null) {
        final producto = result.data!.productos.firstWhere(
          (p) => p['codigo'] == codigo,
          orElse: () => <String, dynamic>{},
        );
        if (producto.isNotEmpty) {
          return ApiResponse.success(producto);
        }
      }
      return ApiResponse.error('Producto no encontrado');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Crear producto (solo nombre; precio y stock se configuran por presentaciones)
  static Future<ApiResponse<Map<String, dynamic>>> crearProducto({
    required String nombre,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/productos/$businessId'),
        headers: headers,
        body: jsonEncode({'nombre': nombre}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return ApiResponse.success(data['producto']);
      } else {
        return ApiResponse.error(data['error'] ?? 'Error creando producto');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  // ==================== PRESENTACIONES ====================

  static Future<ApiResponse<PresentacionesData>> getPresentaciones(String productId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/productos/$businessId/$productId/presentaciones'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['presentaciones'] as List? ?? [])
            .map((p) => Presentacion.fromMap(Map<String, dynamic>.from(p)))
            .toList();
        final availableKg      = (data['availableKg']      as num?)?.toDouble();
        final roastedKg        = (data['roastedKg']        as num?)?.toDouble() ?? 0.0;
        final completedLots    = (data['completedLots'] as List? ?? [])
            .map((l) => LoteCompletado.fromMap(Map<String, dynamic>.from(l)))
            .toList();
        final nextEventKg      = (data['nextEventKg']      as num?)?.toDouble() ?? 0.0;
        final nextEventDate    =  data['nextEventDate']    as String?;
        final nextEventStatus  =  data['nextEventStatus']  as String?;
        final nextEventLotCode =  data['nextEventLotCode'] as String?;
        final nextEventId      =  data['nextEventId']      as String?;
        final greenKg          = (data['greenKg']          as num?)?.toDouble();
        final greenLotCode     =  data['greenLotCode']     as String?;
        final isGreenCoffee    = (data['isGreenCoffee']    as bool?) ?? false;
        return ApiResponse.success(PresentacionesData(
          presentaciones:  list,
          availableKg:     availableKg,
          roastedKg:       roastedKg,
          completedLots:   completedLots,
          nextEventKg:     nextEventKg,
          nextEventDate:   nextEventDate,
          nextEventStatus: nextEventStatus,
          nextEventLotCode:nextEventLotCode,
          nextEventId:     nextEventId,
          greenKg:         greenKg,
          greenLotCode:    greenLotCode,
          isGreenCoffee:   isGreenCoffee,
        ));
      }
      return ApiResponse.error('Error obteniendo presentaciones');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  static Future<ApiResponse<List<Map<String, dynamic>>>> getLotesVerdes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/tostador/green-lots?businessId=$businessId'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final list = (jsonDecode(response.body) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return ApiResponse.success(list);
      }
      return ApiResponse.error('Error obteniendo lotes verdes');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  static Future<ApiResponse<String>> crearEventoTueste({
    required String greenLotId,
    required double greenInKg,
    required String roastedAt,
    required String productId,
    double? roastedOutKg,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/tostador/events/create'),
        headers: headers,
        body: jsonEncode({
          'businessId':      businessId,
          'green_lot_id':    greenLotId,
          'green_in_kg':     greenInKg,
          'roasted_at':      roastedAt,
          'product_id':      productId,
          if (roastedOutKg != null) 'roasted_out_kg': roastedOutKg,
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return ApiResponse.success(data['eventId'] as String? ?? '');
      }
      final err = jsonDecode(response.body)['error'] ?? 'Error creando evento';
      return ApiResponse.error(err);
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  static Future<ApiResponse<Map<String, dynamic>>> crearPresentacion({
    required String productId,
    required num contenido,
    required String unidad,
    required double precio,
    double? precioB2b,
    int? cantidadB2b,
    int stock = 0,
    int pedidoMinimo = 1,
    int orden = 0,
    bool predeterminada = false,
    List<String> molienda = const [],
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/productos/$businessId/$productId/presentaciones'),
        headers: headers,
        body: jsonEncode({
          'contenido': contenido,
          'unidad': unidad,
          'precio': precio,
          if (precioB2b != null) 'precioB2b': precioB2b,
          if (cantidadB2b != null) 'cantidadB2b': cantidadB2b,
          'stock': stock,
          'pedidoMinimo': pedidoMinimo,
          'orden': orden,
          'predeterminada': predeterminada,
          'molienda': molienda,
        }),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return ApiResponse.success(data);
      return ApiResponse.error(data['error'] ?? 'Error creando presentación');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  static Future<ApiResponse<Map<String, dynamic>>> actualizarPresentacion({
    required String productId,
    required String presentationId,
    num? contenido,
    String? unidad,
    double? precio,
    double? precioB2b,
    int? cantidadB2b,
    int? stock,
    int? pedidoMinimo,
    int? orden,
    bool? predeterminada,
    List<String>? molienda,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (contenido != null) body['contenido'] = contenido;
      if (unidad != null) body['unidad'] = unidad;
      if (precio != null) body['precio'] = precio;
      if (precioB2b != null) body['precioB2b'] = precioB2b;
      body['cantidadB2b'] = cantidadB2b;
      if (stock != null) body['stock'] = stock;
      if (pedidoMinimo != null) body['pedidoMinimo'] = pedidoMinimo;
      if (orden != null) body['orden'] = orden;
      if (predeterminada != null) body['predeterminada'] = predeterminada;
      if (molienda != null) body['molienda'] = molienda;

      final response = await http.put(
        Uri.parse('$baseUrl/api/productos/$businessId/$productId/presentaciones/$presentationId'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) return ApiResponse.success(data);
      return ApiResponse.error(data['error'] ?? 'Error actualizando presentación');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  static Future<ApiResponse<void>> eliminarPresentacion({
    required String productId,
    required String presentationId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/productos/$businessId/$productId/presentaciones/$presentationId'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return ApiResponse.success(null);
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error eliminando presentación');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Actualizar kg disponible en lote (product_lot_assignments)
  static Future<ApiResponse<void>> actualizarLoteKg({
    required String productId,
    required double kgDisponible,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/productos/$businessId/$productId/lote'),
        headers: headers,
        body: jsonEncode({'kg_disponible': kgDisponible}),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return ApiResponse.success(null);
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error actualizando lote');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Actualizar producto existente
  /// Get products from any business (used for B2B provider catalog)
  static Future<List<Map<String, dynamic>>> getProductosDeNegocio(String negocioId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/productos/$negocioId?estado=ACTIVO&limite=200'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['productos'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<ApiResponse<Map<String, dynamic>>> actualizarProducto({
    required String codigo,
    String? nombre,
    double? precio,
    int? stock,
    String? descripcion,
    String? categoria,
    String? imagenUrl,
    String? proveedorId,
    String? proveedorProductoCodigo,
    double? precioMayor,
    int? cantidadMayor,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (nombre != null) body['nombre'] = nombre;
      if (precio != null) body['precio'] = precio;
      if (stock != null) body['stock'] = stock;
      if (descripcion != null) body['descripcion'] = descripcion;
      if (categoria != null) body['categoria'] = categoria;
      if (imagenUrl != null) body['imagenUrl'] = imagenUrl;
      if (proveedorId != null) body['proveedorId'] = proveedorId;
      if (proveedorProductoCodigo != null) body['proveedorProductoCodigo'] = proveedorProductoCodigo;
      if (precioMayor != null) body['precioMayor'] = precioMayor;
      if (cantidadMayor != null) body['cantidadMayor'] = cantidadMayor;

      final response = await http.put(
        Uri.parse('$baseUrl/api/productos/$businessId/$codigo'),
        headers: headers,
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data['producto'] ?? data);
      } else {
        return ApiResponse.error(data['error'] ?? 'Error actualizando producto');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Actualizar stock de producto
  static Future<ApiResponse<Map<String, dynamic>>> actualizarStock({
    required String codigo,
    required int cantidad,
    required String operacion, // 'agregar' | 'restar' | 'establecer'
    String? motivo,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/productos/$businessId/$codigo/stock'),
        headers: headers,
        body: jsonEncode({
          'cantidad': cantidad,
          'operacion': operacion,
          if (motivo != null) 'motivo': motivo,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(data['error'] ?? 'Error actualizando stock');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  // ==================== CLIENTES ====================

  /// Obtener todos los clientes
  static Future<ApiResponse<List<Map<String, dynamic>>>> getClientes({
    String? buscar,
    String? ordenar,
  }) async {
    try {
      var url = '$baseUrl/api/clientes/$businessId';
      final params = <String>[];
      if (buscar != null) params.add('buscar=$buscar');
      if (ordenar != null) params.add('ordenar=$ordenar');
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final clientes = List<Map<String, dynamic>>.from(data['clientes'] ?? []);
        return ApiResponse.success(clientes);
      } else {
        return ApiResponse.error('Error obteniendo clientes');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Crear cliente con estructura completa
  static Future<ApiResponse<Map<String, dynamic>>> crearCliente({
    required Map<String, dynamic> datos,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/clientes/$businessId'),
        headers: headers,
        body: jsonEncode(datos),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return ApiResponse.success(data['cliente']);
      } else {
        return ApiResponse.error(data['error'] ?? 'Error creando cliente');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Actualizar cliente existente
  static Future<ApiResponse<Map<String, dynamic>>> actualizarCliente({
    required String clienteId,
    required Map<String, dynamic> datos,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/clientes/$businessId/$clienteId'),
        headers: headers,
        body: jsonEncode(datos),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(data['error'] ?? 'Error actualizando cliente');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Crear dirección de cliente
  static Future<ApiResponse<Map<String, dynamic>>> crearDireccion({
    required String clienteId,
    required String addressLine,
    String? alias,
    String? district,
    String? department,
    String? reference,
    bool isPrimary = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/clientes/$businessId/$clienteId/addresses'),
        headers: headers,
        body: jsonEncode({
          'addressLine': addressLine,
          if (alias != null && alias.isNotEmpty) 'alias': alias,
          if (district != null && district.isNotEmpty) 'district': district,
          if (department != null && department.isNotEmpty) 'department': department,
          if (reference != null && reference.isNotEmpty) 'reference': reference,
          'isPrimary': isPrimary,
        }),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return ApiResponse.success(data['address'] as Map<String, dynamic>);
      }
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error creando dirección');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Eliminar cliente
  static Future<ApiResponse<void>> eliminarCliente(String clienteId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/clientes/$businessId/$clienteId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error eliminando cliente');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Enviar mensaje a cliente
  static Future<ApiResponse<void>> enviarMensaje({
    required String whatsapp,
    required String mensaje,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/mensaje'),
        headers: headers,
        body: jsonEncode({
          'businessId': businessId,
          'to': whatsapp,
          'message': mensaje,
        }),
      );

      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error enviando mensaje');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  // ==================== PEDIDOS ====================

  /// Obtener pedidos con filtro de vista y paginación
  /// [vista]: PENDIENTES | HISTORIAL | POR_COBRAR | PAGADOS
  static Future<ApiResponse<PedidosResponse>> getPedidos({
    String? vista,
    String? estado,
    String? cliente,
    String? tipo,
    int pagina = 1,
    int limite = 50,
  }) async {
    try {
      var url = '$baseUrl/api/pedidos/$businessId';
      final params = <String, String>{};
      if (vista != null) params['vista'] = vista;
      if (estado != null) params['estado'] = estado;
      if (cliente != null) params['cliente'] = cliente;
      if (tipo != null) params['tipo'] = tipo;
      params['pagina'] = pagina.toString();
      params['limite'] = limite.toString();
      
      if (params.isNotEmpty) {
        url += '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
      }

      debugPrint('📡 getPedidos: $url');

      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pedidos = List<Map<String, dynamic>>.from(data['pedidos'] ?? []);
        final respuesta = PedidosResponse(
          pedidos: pedidos,
          total: data['total'] ?? pedidos.length,
          pagina: data['pagina'] ?? pagina,
          totalPaginas: data['totalPaginas'] ?? 1,
          hayMas: data['hayMas'] ?? false,
        );
        debugPrint('📋 getPedidos: ${pedidos.length}/${respuesta.total} (pág ${respuesta.pagina}/${respuesta.totalPaginas})');
        return ApiResponse.success(respuesta);
      } else {
        return ApiResponse.error('Error obteniendo pedidos');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Crear pedido
  static Future<ApiResponse<Map<String, dynamic>>> crearPedido({
    required String whatsapp,
    String? cliente,
    String? telefono,
    String? direccion,
    String? ciudad,
    String? departamento,
    required List<Map<String, dynamic>> productos,
    required double total,
    double costoEnvio = 0,
    String? observaciones,
    String? tipoEnvio,
    String? empresaEnvio,  // nombre courier (Shalom, Olva…) → col N
    String? estado,
    String? estadoPago,
    String? origen,
    bool notificarCliente = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pedidos/$businessId'),
        headers: headers,
        body: jsonEncode({
          'whatsapp': whatsapp,
          if (cliente != null) 'cliente': cliente,
          if (telefono != null) 'telefono': telefono,
          if (direccion != null) 'direccion': direccion,
          if (ciudad != null) 'ciudad': ciudad,
          if (departamento != null) 'departamento': departamento,
          'productos': productos,
          'total': total,
          'costoEnvio': costoEnvio,
          if (observaciones != null) 'observaciones': observaciones,
          if (tipoEnvio != null) 'tipoEnvio': tipoEnvio,
          if (empresaEnvio != null) 'empresaEnvio': empresaEnvio,
          if (estado != null) 'estado': estado,
          if (estadoPago != null) 'estadoPago': estadoPago,
          if (origen != null) 'origen': origen,
          'notificarCliente': notificarCliente,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(data['error'] ?? 'Error creando pedido');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Crear pedido B2B en el negocio proveedor
  static Future<ApiResponse<Map<String, dynamic>>> crearPedidoB2B({
    required String proveedorId,
    required List<Map<String, dynamic>> productos,
    required double total,
    String? observaciones,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pedidos/$proveedorId'),
        headers: headers,
        body: jsonEncode({
          'whatsapp': businessId,
          'cliente': businessName,
          'productos': productos,
          'total': total,
          'tipo': 'B2B',
          'negocioSolicitante': businessId,
          if (observaciones != null) 'observaciones': observaciones,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return ApiResponse.success(data);
      } else {
        return ApiResponse.error(data['error'] ?? 'Error creando pedido B2B');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Get B2B pedidos sent by this business to a specific provider
  static Future<ApiResponse<PedidosResponse>> getPedidosSolicitados(
    String proveedorId, {
    int pagina = 1,
    int limite = 50,
  }) async {
    try {
      final url = '$baseUrl/api/pedidos/$proveedorId'
          '?tipo=B2B'
          '&negocioSolicitante=${Uri.encodeComponent(businessId)}'
          '&pagina=$pagina'
          '&limite=$limite';
      debugPrint('📡 getPedidosSolicitados[$proveedorId]: $url');

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pedidos =
            List<Map<String, dynamic>>.from(data['pedidos'] ?? []);
        return ApiResponse.success(PedidosResponse(
          pedidos: pedidos,
          total: data['total'] ?? pedidos.length,
          pagina: data['pagina'] ?? pagina,
          totalPaginas: data['totalPaginas'] ?? 1,
          hayMas: data['hayMas'] ?? false,
        ));
      } else {
        return ApiResponse.error('Error obteniendo solicitudes enviadas');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Obtener registro de Delivery para un pedido específico
  static Future<Map<String, dynamic>?> getDelivery(String pedidoId) async {
    try {
      final url = '$baseUrl/api/delivery/$businessId?pedidoId=${Uri.encodeComponent(pedidoId)}';
      final response = await http.get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final deliveries = data['deliveries'] as List?;
        if (deliveries != null && deliveries.isNotEmpty) {
          return Map<String, dynamic>.from(deliveries.first as Map);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[ApiService] getDelivery error: $e');
      return null;
    }
  }

  /// Actualizar estado de pedido
  static Future<ApiResponse<void>> actualizarPedido({
    required String pedidoId,
    String? estado,
    String? observaciones,
    String? direccion,
    bool notificarCliente = false,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/pedidos/$businessId/$pedidoId'),
        headers: headers,
        body: jsonEncode({
          if (estado != null) 'estado': estado,
          if (observaciones != null) 'observaciones': observaciones,
          if (direccion != null) 'direccion': direccion,
          'notificarCliente': notificarCliente,
        }),
      );

      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(
          data['error'] ?? 'Error actualizando pedido',
          code: data['code'],
        );
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  static Future<ApiResponse<void>> actualizarItemPedido({
    required String pedidoId,
    String? presentacionId,
    String? codigo,
    required int cantidad,
    String? grind,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/pedidos/$businessId/$pedidoId/items'),
        headers: headers,
        body: jsonEncode({
          if (presentacionId != null && presentacionId.isNotEmpty)
            'presentacionId': presentacionId,
          if (codigo != null && codigo.isNotEmpty) 'codigo': codigo,
          'cantidad': cantidad,
          if (grind != null && grind.isNotEmpty) 'grind': grind,
        }),
      );
      if (response.statusCode == 200) return ApiResponse.success(null);
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error actualizando producto');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  static Future<ApiResponse<void>> actualizarCostoEnvio({
    required String pedidoId,
    required double costoEnvio,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/pedidos/$businessId/$pedidoId/shipping'),
        headers: headers,
        body: jsonEncode({'costoEnvio': costoEnvio}),
      );
      if (response.statusCode == 200) return ApiResponse.success(null);
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error actualizando costo de envío');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  // ==================== UPLOAD A SUPABASE STORAGE ====================

  /// Subir imagen usando signed URL (sin base64, sin pasar el archivo por el backend).
  /// Paso 1: pide signed URL al backend.
  /// Paso 2: sube bytes directamente a Supabase Storage.
  /// Paso 3: retorna la URL pública.
  static Future<ApiResponse<String>> uploadImage(File imageFile, {String? folder}) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final extension = imageFile.path.split('.').last.toLowerCase();
      String mimeType = 'image/jpeg';
      if (extension == 'png')  mimeType = 'image/png';
      if (extension == 'webp') mimeType = 'image/webp';
      final fname = '${DateTime.now().millisecondsSinceEpoch}.$extension';

      debugPrint('[uploadImage] archivo=${imageFile.path} tamaño=${bytes.length}B mime=$mimeType');

      // Paso 1 — obtener URL firmada
      debugPrint('[uploadImage] Paso 1: solicitando signed URL...');
      final signRes = await http.post(
        Uri.parse('$baseUrl/api/upload/$businessId/sign'),
        headers: headers,
        body: jsonEncode({
          'filename': fname,
          'mimeType': mimeType,
          if (folder != null) 'folder': folder,
        }),
      ).timeout(const Duration(seconds: 15));

      debugPrint('[uploadImage] sign status=${signRes.statusCode} body=${signRes.body}');

      if (signRes.statusCode != 200) {
        final d = jsonDecode(signRes.body);
        return ApiResponse.error(d['error'] ?? 'Error obteniendo URL firmada (${signRes.statusCode})');
      }
      final signData  = jsonDecode(signRes.body) as Map<String, dynamic>;
      final signedUrl = signData['signedUrl'] as String;
      final publicUrl = signData['publicUrl'] as String;

      // Paso 2 — subir bytes directamente a Supabase Storage (sin base64)
      debugPrint('[uploadImage] Paso 2: PUT a Supabase Storage...');
      debugPrint('[uploadImage] signedUrl=$signedUrl');
      final putRes = await http.put(
        Uri.parse(signedUrl),
        headers: {'Content-Type': mimeType},
        body: bytes,
      ).timeout(const Duration(seconds: 60));

      debugPrint('[uploadImage] PUT status=${putRes.statusCode} body=${putRes.body}');

      if (putRes.statusCode != 200 && putRes.statusCode != 204) {
        return ApiResponse.error(
          'Error subiendo archivo (HTTP ${putRes.statusCode}): ${putRes.body}',
        );
      }

      debugPrint('[uploadImage] ✅ Subido correctamente. publicUrl=$publicUrl');
      return ApiResponse.success(publicUrl);
    } catch (e) {
      debugPrint('[uploadImage] ❌ Excepción: $e');
      return ApiResponse.error('Error subiendo imagen: $e');
    }
  }

  /// Eliminar un archivo de Supabase Storage via backend.
  static Future<void> eliminarArchivoStorage({
    required String businessId,
    required String storagePath,
  }) async {
    await http.delete(
      Uri.parse('$baseUrl/api/upload/$businessId/${Uri.encodeComponent(storagePath)}'),
      headers: headers,
    ).timeout(const Duration(seconds: 10));
  }

  /// Subir múltiples imágenes
  static Future<List<String>> uploadImages(List<File> images, {String? folder}) async {
    final urls = <String>[];
    for (final image in images) {
      final result = await uploadImage(image, folder: folder);
      if (result.isSuccess && result.data != null) {
        urls.add(result.data!);
      }
    }
    return urls;
  }

  // ==================== HEALTH ====================

  /// Verificar conexión con el servidor
  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==================== PRECIOS PERSONALIZADOS ====================

  /// Obtener precios personalizados de un cliente
  static Future<ApiResponse<Map<String, double>>> getPreciosCliente({
    required String clienteId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/precios-cliente/$businessId/$clienteId'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final preciosRaw = data['precios'] as Map<String, dynamic>? ?? {};
        
        // Convertir a Map<String, double>
        final precios = <String, double>{};
        preciosRaw.forEach((codigo, value) {
          if (value is Map) {
            precios[codigo] = (value['precio'] ?? 0).toDouble();
          } else {
            precios[codigo] = (value ?? 0).toDouble();
          }
        });
        
        return ApiResponse.success(precios);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error obteniendo precios');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Eliminar precio personalizado de un cliente para una presentación
  static Future<ApiResponse<bool>> eliminarPrecioCliente({
    required String clienteId,
    required String presentationId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/precios-cliente/$businessId/$clienteId/$presentationId'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return ApiResponse.success(true);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error eliminando precio');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Guardar precios personalizados de un cliente
  static Future<ApiResponse<bool>> guardarPreciosCliente({
    required String clienteId,
    required Map<String, double> precios,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/precios-cliente/$businessId/$clienteId'),
        headers: headers,
        body: jsonEncode({
          'precios': precios,
          'usuario': 'APP',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return ApiResponse.success(true);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error guardando precios');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  // ==================== PUSH NOTIFICATIONS ====================

  /// Registrar token FCM para push notifications
  static Future<ApiResponse<bool>> registrarTokenPush({required String token}) async {
    try {
      // Detectar plataforma automáticamente
      String platform = 'unknown';
      if (Platform.isIOS) {
        platform = 'ios';
      } else if (Platform.isAndroid) {
        platform = 'android';
      }

      final url = '$baseUrl/api/push-token/$businessId';
      print('🔔 Registrando token FCM:');
      print('   URL: $url');
      print('   BusinessId: $businessId');
      print('   Platform: $platform');
      print('   Token: ${token.substring(0, 30)}...');

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode({
          'token': token,
          'platform': platform,
          'appVersion': '1.0.2',
        }),
      ).timeout(const Duration(seconds: 10));

      print('   Response: ${response.statusCode}');
      print('   Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Token FCM registrado correctamente en el servidor');
        return ApiResponse.success(true);
      } else {
        final data = jsonDecode(response.body);
        print('❌ Error registrando token: ${data['error']}');
        return ApiResponse.error(data['error'] ?? 'Error registrando token');
      }
    } catch (e) {
      print('❌ Excepción registrando token: $e');
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Eliminar token FCM (al cerrar sesión)
  static Future<ApiResponse<bool>> eliminarTokenPush({required String token}) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/push-token/$businessId'),
        headers: headers,
        body: jsonEncode({'token': token}),
      ).timeout(const Duration(seconds: 10));

      return ApiResponse.success(response.statusCode == 200);
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  // ==================== EVIDENCIAS DE PAGO ====================

  /// Agregar evidencia de pago a un pedido.
  /// [paymentId] vincula el comprobante a un pago específico (Supabase).
  /// Agrega evidencia y retorna el objeto guardado (incluye el `id` para poder eliminarlo).
  static Future<ApiResponse<Map<String, dynamic>>> agregarEvidenciaPago({
    required String pedidoId,
    required Map<String, dynamic> evidencia,
    String? paymentId,
  }) async {
    try {
      final body = Map<String, dynamic>.from(evidencia);
      if (paymentId != null) body['paymentId'] = paymentId;
      final response = await http.post(
        Uri.parse('$baseUrl/api/pedidos/$businessId/$pedidoId/evidencias'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // El backend retorna { evidencia: { id, url, tipo, fecha, paymentId, ... } }
        final saved = data['evidencia'] as Map<String, dynamic>? ?? evidencia;
        return ApiResponse.success(Map<String, dynamic>.from(saved));
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error agregando evidencia');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Eliminar evidencia de pago
  static Future<ApiResponse<bool>> eliminarEvidenciaPago({
    required String pedidoId,
    required String evidenciaId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/pedidos/$businessId/$pedidoId/evidencias/$evidenciaId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return ApiResponse.success(true);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error eliminando evidencia');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Eliminar un pago registrado (y sus comprobantes en cascada).
  /// Retorna el estado actualizado: { estadoPago, montoPagado, pagos, evidencias }
  static Future<ApiResponse<Map<String, dynamic>>> eliminarPago({
    required String pedidoId,
    required String pagoId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/pedidos/$businessId/$pedidoId/pagos/$pagoId'),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(data);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error eliminando pago');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Actualizar estado de pago de un pedido.
  /// Usa [nuevoPago] para acumular un pago parcial (se suma al historial).
  /// Usa [montoPagado] solo para reemplazar directamente (ej: revertir a 0).
  static Future<ApiResponse<Map<String, dynamic>>> actualizarEstadoPago({
    required String pedidoId,
    required String estadoPago,
    double? montoPagado,
    double? nuevoPago,
    String? notaPago,
  }) async {
    try {
      final body = <String, dynamic>{
        'estadoPago': estadoPago,
      };
      if (nuevoPago != null && nuevoPago > 0) {
        body['nuevoPago'] = nuevoPago;
        if (notaPago != null && notaPago.isNotEmpty) body['notaPago'] = notaPago;
      } else if (montoPagado != null) {
        body['montoPagado'] = montoPagado;
      }
      if (estadoPago == 'PAGADO') {
        body['fechaPago'] = DateTime.now().toIso8601String();
      }

      final response = await http.put(
        Uri.parse('$baseUrl/api/pedidos/$businessId/$pedidoId'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.success(data);
      } else {
        final data = jsonDecode(response.body);
        return ApiResponse.error(data['error'] ?? 'Error actualizando estado de pago');
      }
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }
  // ─────────────────────────────────────────────────────────────
  // RECETAS (Production Recipes)
  // ─────────────────────────────────────────────────────────────

  /// Get all recipes for this business.
  /// Optionally filter by [codigoDestino] to get only recipes that produce a specific product.
  static Future<ApiResponse<List<Receta>>> getRecetas({String? codigoDestino}) async {
    try {
      var url = '$baseUrl/api/recetas/$businessId';
      if (codigoDestino != null && codigoDestino.isNotEmpty) {
        url += '?codigoDestino=${Uri.encodeComponent(codigoDestino)}';
      }
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = (data['recetas'] as List? ?? [])
            .map((r) => Receta.fromMap(Map<String, dynamic>.from(r)))
            .toList();
        return ApiResponse.success(list);
      }
      return ApiResponse.error('Error obteniendo recetas');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Create a new production recipe.
  static Future<ApiResponse<String>> crearReceta({
    required String codigoDestino,
    required String nombreDestino,
    required double cantidadDestino,
    required String codigoOrigen,
    required String nombreOrigen,
    required double cantidadOrigen,
    String descripcion = '',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/recetas/$businessId'),
            headers: headers,
            body: jsonEncode({
              'codigoDestino': codigoDestino,
              'nombreDestino': nombreDestino,
              'cantidadDestino': cantidadDestino,
              'codigoOrigen': codigoOrigen,
              'nombreOrigen': nombreOrigen,
              'cantidadOrigen': cantidadOrigen,
              'descripcion': descripcion,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return ApiResponse.success(data['id'] as String);
      }
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error creando receta');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Update an existing recipe.
  static Future<ApiResponse<void>> actualizarReceta(
    String recetaId,
    Map<String, dynamic> changes,
  ) async {
    try {
      final response = await http
          .put(
            Uri.parse('$baseUrl/api/recetas/$businessId/$recetaId'),
            headers: headers,
            body: jsonEncode(changes),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return ApiResponse.success(null);
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error actualizando receta');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Delete a recipe (soft delete).
  static Future<ApiResponse<void>> eliminarReceta(String recetaId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$baseUrl/api/recetas/$businessId/$recetaId'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) return ApiResponse.success(null);
      final data = jsonDecode(response.body);
      return ApiResponse.error(data['error'] ?? 'Error eliminando receta');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Get fulfillment plan for a specific pedido.
  /// Returns per-product: stock status + recipe suggestions with viability.
  static Future<ApiResponse<FulfillmentPlan>> getPlanAtencion(String pedidoId) async {
    try {
      final url = '$baseUrl/api/recetas/$businessId/plan/$pedidoId';
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ApiResponse.success(FulfillmentPlan.fromMap(data));
      }
      return ApiResponse.error('Error obteniendo plan de atención');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  // ==================== PRE-VENTAS ====================

  /// Lista eventos de tostado con offers disponibles para pre-orden
  static Future<ApiResponse<List<Map<String, dynamic>>>> getEventosPreventas() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/preventas/$businessId/eventos'), headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return ApiResponse.success(data.cast<Map<String, dynamic>>());
      }
      return ApiResponse.error('Error obteniendo eventos');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Crea un pedido de tipo PREVENTA vinculado a un tueste programado.
  /// Usa el mismo endpoint que crearPedido pero añade tipo='PREVENTA' y sourceEventId.
  static Future<ApiResponse<Map<String, dynamic>>> crearPreventaPedido({
    required String whatsapp,
    required String sourceEventId,
    String? cliente,
    String? telefono,
    String? direccion,
    String? ciudad,
    String? departamento,
    required List<Map<String, dynamic>> productos,
    required double total,
    double costoEnvio = 0,
    String? observaciones,
    String? tipoEnvio,
    String? empresaEnvio,
    bool notificarCliente = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/pedidos/$businessId'),
        headers: headers,
        body: jsonEncode({
          'whatsapp':        whatsapp,
          'tipo':            'PREVENTA',
          'sourceEventId':   sourceEventId,
          if (cliente != null)      'cliente':      cliente,
          if (telefono != null)     'telefono':     telefono,
          if (direccion != null)    'direccion':    direccion,
          if (ciudad != null)       'ciudad':       ciudad,
          if (departamento != null) 'departamento': departamento,
          'productos':       productos,
          'total':           total,
          'costoEnvio':      costoEnvio,
          if (observaciones != null) 'observaciones': observaciones,
          if (tipoEnvio != null)    'tipoEnvio':    tipoEnvio,
          if (empresaEnvio != null) 'empresaEnvio': empresaEnvio,
          'notificarCliente': notificarCliente,
        }),
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 201) return ApiResponse.success(data);
      return ApiResponse.error(data['error'] ?? 'Error creando pre-venta');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }

  /// Crea una pre-orden para un cliente
  static Future<ApiResponse<Map<String, dynamic>>> crearPreorden({
    required String offerId,
    required String sourceEventId,
    String? presentationId,
    int cantidad = 1,
    required String clienteNombre,
    required String clienteWhatsapp,
    String? clienteEmail,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/preventas/$businessId'),
            headers: headers,
            body: jsonEncode({
              'offerId': offerId,
              'sourceEventId': sourceEventId,
              if (presentationId != null) 'presentationId': presentationId,
              'cantidad': cantidad,
              'cliente': {
                'nombre': clienteNombre,
                'whatsapp': clienteWhatsapp,
                if (clienteEmail != null) 'email': clienteEmail,
              },
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) return ApiResponse.success(data);
      return ApiResponse.error(data['error'] ?? 'Error creando pre-orden');
    } catch (e) {
      return ApiResponse.error('Error de conexión: $e');
    }
  }
}

/// Clase para respuestas de la API
class ApiResponse<T> {
  final bool isSuccess;
  final T? data;
  final String? error;
  final String? code;

  ApiResponse._({required this.isSuccess, this.data, this.error, this.code});

  factory ApiResponse.success(T data) => ApiResponse._(
    isSuccess: true,
    data: data,
  );

  factory ApiResponse.error(String error, {String? code}) => ApiResponse._(
    isSuccess: false,
    error: error,
    code: code,
  );
}

/// Respuesta paginada de productos
class ProductosResponse {
  final List<Map<String, dynamic>> productos;
  final int total;
  final int pagina;
  final int totalPaginas;
  final bool hayMas;

  ProductosResponse({
    required this.productos,
    required this.total,
    required this.pagina,
    required this.totalPaginas,
    required this.hayMas,
  });
}

/// Respuesta paginada de pedidos
class PedidosResponse {
  final List<Map<String, dynamic>> pedidos;
  final int total;
  final int pagina;
  final int totalPaginas;
  final bool hayMas;

  PedidosResponse({
    required this.pedidos,
    required this.total,
    required this.pagina,
    required this.totalPaginas,
    required this.hayMas,
  });
}

// ─────────────────────────────────────────────────────────────
// PRESENTACION model
// ─────────────────────────────────────────────────────────────

class LoteCompletado {
  final double kg;
  final String? roastedAt;  // ISO date string
  final String? lotCode;

  const LoteCompletado({required this.kg, this.roastedAt, this.lotCode});

  factory LoteCompletado.fromMap(Map<String, dynamic> m) => LoteCompletado(
    kg:        (m['kg'] as num?)?.toDouble() ?? 0,
    roastedAt: m['roastedAt'] as String?,
    lotCode:   m['lotCode']   as String?,
  );
}

class PresentacionesData {
  final List<Presentacion> presentaciones;
  final double? availableKg;           // kg de eventos completados; null = sin lotes
  final double roastedKg;              // total kg de lotes completados
  final List<LoteCompletado> completedLots; // detalle por lote (con fecha de tueste)
  final double nextEventKg;            // kg ofrecidos en el próximo evento
  final String? nextEventDate;         // fecha ISO del próximo evento
  final String? nextEventStatus;       // 'planned' | 'in_progress'
  final String? nextEventLotCode;      // código de lote del próximo evento
  final String? nextEventId;           // UUID del próximo evento de tostado
  final double? greenKg;               // kg disponibles de lote verde (null = no es café verde)
  final String? greenLotCode;          // código del lote verde
  final bool isGreenCoffee;            // true si el producto tiene green_lot_id

  const PresentacionesData({
    required this.presentaciones,
    this.availableKg,
    this.roastedKg = 0,
    this.completedLots = const [],
    this.nextEventKg = 0,
    this.nextEventDate,
    this.nextEventStatus,
    this.nextEventLotCode,
    this.nextEventId,
    this.greenKg,
    this.greenLotCode,
    this.isGreenCoffee = false,
  });
}

class Presentacion {
  final String id;
  final num contenido;
  final String unidad;
  final double precio;
  final double? precioB2b;
  final int? cantidadB2b;
  final int stock;
  final int pedidoMinimo;
  final int orden;
  final bool predeterminada;
  final List<String> molienda;
  final String? imageUrl;

  const Presentacion({
    required this.id,
    required this.contenido,
    required this.unidad,
    required this.precio,
    this.precioB2b,
    this.cantidadB2b,
    required this.stock,
    required this.pedidoMinimo,
    required this.orden,
    required this.predeterminada,
    required this.molienda,
    this.imageUrl,
  });

  factory Presentacion.fromMap(Map<String, dynamic> m) => Presentacion(
        id:            m['id']?.toString() ?? '',
        contenido:     (m['contenido'] as num?) ?? 1,
        unidad:        m['unidad']?.toString() ?? 'und',
        precio:        (m['precio'] as num?)?.toDouble() ?? 0,
        precioB2b:     m['precioB2b'] != null ? (m['precioB2b'] as num).toDouble() : null,
        cantidadB2b:   m['cantidadB2b'] != null ? (m['cantidadB2b'] as num).toInt() : null,
        stock:         (m['stock'] as num?)?.toInt() ?? 0,
        pedidoMinimo:  (m['pedidoMinimo'] as num?)?.toInt() ?? 1,
        orden:         (m['orden'] as num?)?.toInt() ?? 0,
        predeterminada: m['predeterminada'] == true,
        molienda:      (m['molienda'] as List?)?.map((e) => e.toString()).toList() ?? [],
        imageUrl:      (m['imageUrl'] ?? m['image_url']) as String?,
      );

  String get etiqueta {
    final c = contenido.toDouble();
    if (unidad == 'g' && c >= 1000) {
      final kg = c / 1000;
      return '${kg % 1 == 0 ? kg.toInt() : kg}kg';
    }
    return '${c % 1 == 0 ? contenido.toInt() : contenido}$unidad';
  }
}

// ─────────────────────────────────────────────────────────────
// RECETAS models
// ─────────────────────────────────────────────────────────────

/// A production recipe:
/// "consume [cantidadOrigen] units of [codigoOrigen] → produce [cantidadDestino] units of [codigoDestino]"
class Receta {
  final String id;
  final String codigoDestino;
  final String nombreDestino;
  final double cantidadDestino;
  final String codigoOrigen;
  final String nombreOrigen;
  final double cantidadOrigen;
  final String descripcion;
  final String fecha;

  const Receta({
    required this.id,
    required this.codigoDestino,
    required this.nombreDestino,
    required this.cantidadDestino,
    required this.codigoOrigen,
    required this.nombreOrigen,
    required this.cantidadOrigen,
    this.descripcion = '',
    this.fecha = '',
  });

  factory Receta.fromMap(Map<String, dynamic> m) => Receta(
        id:               m['id']?.toString() ?? '',
        codigoDestino:    m['codigoDestino']?.toString() ?? '',
        nombreDestino:    m['nombreDestino']?.toString() ?? '',
        cantidadDestino:  (m['cantidadDestino'] as num?)?.toDouble() ?? 1,
        codigoOrigen:     m['codigoOrigen']?.toString() ?? '',
        nombreOrigen:     m['nombreOrigen']?.toString() ?? '',
        cantidadOrigen:   (m['cantidadOrigen'] as num?)?.toDouble() ?? 1,
        descripcion:      m['descripcion']?.toString() ?? '',
        fecha:            m['fecha']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'codigoDestino': codigoDestino,
        'nombreDestino': nombreDestino,
        'cantidadDestino': cantidadDestino,
        'codigoOrigen': codigoOrigen,
        'nombreOrigen': nombreOrigen,
        'cantidadOrigen': cantidadOrigen,
        'descripcion': descripcion,
      };
}

/// One suggestion inside a PlanItem: use a specific recipe to cover the deficit
class RecetaSugerencia {
  final String recetaId;
  final String descripcion;
  final String codigoOrigen;
  final String nombreOrigen;
  final double stockOrigen;
  final double cantidadOrigen;   // units consumed per batch
  final double cantidadDestino;  // units produced per batch
  final double origenNecesario;  // total origin needed to cover deficit
  final bool posible;            // enough origin stock?
  final double maxProducible;    // max destination units producible right now
  final double stockOrigenInsuficiente; // how much more origin is needed

  const RecetaSugerencia({
    required this.recetaId,
    required this.descripcion,
    required this.codigoOrigen,
    required this.nombreOrigen,
    required this.stockOrigen,
    required this.cantidadOrigen,
    required this.cantidadDestino,
    required this.origenNecesario,
    required this.posible,
    required this.maxProducible,
    required this.stockOrigenInsuficiente,
  });

  factory RecetaSugerencia.fromMap(Map<String, dynamic> m) => RecetaSugerencia(
        recetaId:                 m['recetaId']?.toString() ?? '',
        descripcion:              m['descripcion']?.toString() ?? '',
        codigoOrigen:             m['codigoOrigen']?.toString() ?? '',
        nombreOrigen:             m['nombreOrigen']?.toString() ?? '',
        stockOrigen:              (m['stockOrigen'] as num?)?.toDouble() ?? 0,
        cantidadOrigen:           (m['cantidadOrigen'] as num?)?.toDouble() ?? 1,
        cantidadDestino:          (m['cantidadDestino'] as num?)?.toDouble() ?? 1,
        origenNecesario:          (m['origenNecesario'] as num?)?.toDouble() ?? 0,
        posible:                  m['posible'] == true,
        maxProducible:            (m['maxProducible'] as num?)?.toDouble() ?? 0,
        stockOrigenInsuficiente:  (m['stockOrigenInsuficiente'] as num?)?.toDouble() ?? 0,
      );
}

/// Fulfillment status for one product line in a pedido
class PlanItem {
  final String codigo;
  final String nombre;
  final double cantidad;      // ordered quantity
  final double stockActual;   // current direct stock
  final double deficit;       // how much is missing from direct stock
  final bool cubierto;        // deficit == 0
  final bool parcial;         // has some stock but not enough
  final List<RecetaSugerencia> sugerencias;

  const PlanItem({
    required this.codigo,
    required this.nombre,
    required this.cantidad,
    required this.stockActual,
    required this.deficit,
    required this.cubierto,
    required this.parcial,
    required this.sugerencias,
  });

  factory PlanItem.fromMap(Map<String, dynamic> m) => PlanItem(
        codigo:      m['codigo']?.toString() ?? '',
        nombre:      m['nombre']?.toString() ?? '',
        cantidad:    (m['cantidad'] as num?)?.toDouble() ?? 0,
        stockActual: (m['stockActual'] as num?)?.toDouble() ?? 0,
        deficit:     (m['deficit'] as num?)?.toDouble() ?? 0,
        cubierto:    m['cubierto'] == true,
        parcial:     m['parcial'] == true,
        sugerencias: (m['sugerencias'] as List? ?? [])
            .map((s) => RecetaSugerencia.fromMap(Map<String, dynamic>.from(s)))
            .toList(),
      );
}

/// Full fulfillment plan for a pedido
class FulfillmentPlan {
  final String pedidoId;
  final List<PlanItem> plan;
  final bool todoCubierto;
  final bool algunoSinStock;

  const FulfillmentPlan({
    required this.pedidoId,
    required this.plan,
    required this.todoCubierto,
    required this.algunoSinStock,
  });

  factory FulfillmentPlan.fromMap(Map<String, dynamic> m) => FulfillmentPlan(
        pedidoId:       m['pedidoId']?.toString() ?? '',
        plan:           (m['plan'] as List? ?? [])
            .map((p) => PlanItem.fromMap(Map<String, dynamic>.from(p)))
            .toList(),
        todoCubierto:   m['todoCubierto'] == true,
        algunoSinStock: m['algunoSinStock'] == true,
      );
}
