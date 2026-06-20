// Export all models
export 'bot_conversation.dart';

/// Modelo de Producto
class Producto {
  final String codigo;
  final String nombre;
  final String? descripcion;
  final double precio;
  final int stock;
  final int stockReservado;
  final String? imagenUrl;
  final String estado;
  final String? categoria;
  final double precioMayor;
  final int cantidadMayor;

  Producto({
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.precio,
    required this.stock,
    this.stockReservado = 0,
    this.imagenUrl,
    this.estado = 'ACTIVO',
    this.categoria,
    this.precioMayor = 0,
    this.cantidadMayor = 0,
  });

  int get disponible => stock - stockReservado;

  factory Producto.fromJson(Map<String, dynamic> json) {
    return Producto(
      codigo: json['codigo'] ?? '',
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      precio: (json['precio'] ?? 0).toDouble(),
      stock: json['stock'] ?? 0,
      stockReservado: json['stockReservado'] ?? 0,
      imagenUrl: json['imagenUrl'],
      estado: json['estado'] ?? 'ACTIVO',
      categoria: json['categoria'],
      precioMayor: (json['precioMayor'] ?? 0).toDouble(),
      cantidadMayor: (json['cantidadMayor'] ?? 0) as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'codigo': codigo,
      'nombre': nombre,
      'descripcion': descripcion,
      'precio': precio,
      'stock': stock,
      'stockReservado': stockReservado,
      'imagenUrl': imagenUrl,
      'estado': estado,
      'categoria': categoria,
      'precioMayor': precioMayor,
      'cantidadMayor': cantidadMayor,
    };
  }
}

/// Modelo de Cliente
class Cliente {
  final String id;
  final String whatsapp;
  final String nombre;
  final String? telefono;
  final String? direccion;
  final String? fechaRegistro;
  final String? ultimaCompra;
  final String? departamento;
  final String? ciudad;
  final String? empresa;
  final String? notas;

  Cliente({
    required this.id,
    required this.whatsapp,
    required this.nombre,
    this.telefono,
    this.direccion,
    this.fechaRegistro,
    this.ultimaCompra,
    this.departamento,
    this.ciudad,
    this.empresa,
    this.notas,
  });

  factory Cliente.fromJson(Map<String, dynamic> json) {
    return Cliente(
      id: json['id'] ?? '',
      whatsapp: json['whatsapp'] ?? '',
      nombre: json['nombre'] ?? '',
      telefono: json['telefono'],
      direccion: json['direccion'],
      fechaRegistro: json['fechaRegistro'],
      ultimaCompra: json['ultimaCompra'],
      departamento: json['departamento'],
      ciudad: json['ciudad'],
      empresa: json['empresa'],
      notas: json['notas'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'whatsapp': whatsapp,
      'nombre': nombre,
      'telefono': telefono,
      'direccion': direccion,
      'fechaRegistro': fechaRegistro,
      'ultimaCompra': ultimaCompra,
      'departamento': departamento,
      'ciudad': ciudad,
      'empresa': empresa,
      'notas': notas,
    };
  }
}

/// Modelo de Pedido
class Pedido {
  final String id;
  final String fecha;
  final String? hora;
  final String whatsapp;
  final String cliente;
  final String? telefono;
  final String? direccion;
  final String productos;
  final double total;
  final String estado;
  final String? voucherUrls;
  final String? observaciones;

  Pedido({
    required this.id,
    required this.fecha,
    this.hora,
    required this.whatsapp,
    required this.cliente,
    this.telefono,
    this.direccion,
    required this.productos,
    required this.total,
    required this.estado,
    this.voucherUrls,
    this.observaciones,
  });

  factory Pedido.fromJson(Map<String, dynamic> json) {
    return Pedido(
      id: json['id'] ?? '',
      fecha: json['fecha'] ?? '',
      hora: json['hora'],
      whatsapp: json['whatsapp'] ?? '',
      cliente: json['cliente'] ?? '',
      telefono: json['telefono'],
      direccion: json['direccion'],
      productos: json['productos'] ?? '',
      total: (json['total'] ?? 0).toDouble(),
      estado: json['estado'] ?? '',
      voucherUrls: json['voucherUrls'],
      observaciones: json['observaciones'],
    );
  }
}
