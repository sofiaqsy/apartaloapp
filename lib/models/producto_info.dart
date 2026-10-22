/// Opción de un catálogo (categoría, variedad, tueste, proceso, secado).
class OpcionCatalogo {
  final String id;
  final String nombre;
  const OpcionCatalogo({required this.id, required this.nombre});

  factory OpcionCatalogo.fromMap(Map<String, dynamic> m) =>
      OpcionCatalogo(id: m['id']?.toString() ?? '', nombre: m['nombre']?.toString() ?? '');
}

/// Moneda disponible (S/., $, ...).
class OpcionMoneda {
  final String codigo;
  final String nombre;
  final String simbolo;
  const OpcionMoneda({required this.codigo, required this.nombre, required this.simbolo});

  factory OpcionMoneda.fromMap(Map<String, dynamic> m) => OpcionMoneda(
        codigo: m['codigo']?.toString() ?? '',
        nombre: m['nombre']?.toString() ?? '',
        simbolo: m['simbolo']?.toString() ?? '',
      );

  /// "S/. — Sol peruano (PEN)"
  String get etiqueta => '$simbolo — $nombre ($codigo)';
}

/// Lote verde que se puede vender, con su descripción ya armada por el servidor.
class LoteVerdeOpcion {
  final String id;
  final String etiqueta;
  final double kgDisponibles;
  const LoteVerdeOpcion({required this.id, required this.etiqueta, this.kgDisponibles = 0});

  factory LoteVerdeOpcion.fromMap(Map<String, dynamic> m) => LoteVerdeOpcion(
        id: m['id']?.toString() ?? '',
        etiqueta: m['etiqueta']?.toString() ?? '',
        kgDisponibles: (m['kgDisponibles'] as num?)?.toDouble() ?? 0,
      );
}

/// Catálogos para los selectores de "Información general" y de los ajustes de presentaciones.
class CatalogosProducto {
  final List<OpcionCatalogo> categorias;
  final List<OpcionCatalogo> variedades;
  final List<OpcionCatalogo> tuestes;
  final List<OpcionCatalogo> procesos;
  final List<OpcionCatalogo> secados;
  final List<String> notasSugeridas;
  final List<OpcionMoneda> monedas;
  final List<LoteVerdeOpcion> lotesVerdes;

  const CatalogosProducto({
    this.categorias = const [],
    this.variedades = const [],
    this.tuestes = const [],
    this.procesos = const [],
    this.secados = const [],
    this.notasSugeridas = const [],
    this.monedas = const [],
    this.lotesVerdes = const [],
  });

  static List<OpcionCatalogo> _opciones(dynamic v) =>
      ((v as List?) ?? const []).map((e) => OpcionCatalogo.fromMap(Map<String, dynamic>.from(e as Map))).toList();

  factory CatalogosProducto.fromMap(Map<String, dynamic> m) => CatalogosProducto(
        categorias: _opciones(m['categorias']),
        variedades: _opciones(m['variedades']),
        tuestes: _opciones(m['tuestes']),
        procesos: _opciones(m['procesos']),
        secados: _opciones(m['secados']),
        notasSugeridas: ((m['notasSugeridas'] as List?) ?? const []).map((e) => e.toString()).toList(),
        monedas: ((m['monedas'] as List?) ?? const []).map((e) => OpcionMoneda.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
        lotesVerdes: ((m['lotesVerdes'] as List?) ?? const []).map((e) => LoteVerdeOpcion.fromMap(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

/// Información general de un producto (lo que se edita en la sección "Información general").
class ProductoInfo {
  final String id;
  final String nombre;
  final String descripcionBreve;
  final String detalle;
  final String? categoriaId;
  final String? variedadId;
  final String? tuesteId;
  final String? procesoId;
  final String? secadoId;
  final List<String> notasSensoriales;
  final bool stockManual;
  final String? moneda; // código, por ejemplo PEN
  final String? loteVerdeId;

  const ProductoInfo({
    required this.id,
    required this.nombre,
    this.descripcionBreve = '',
    this.detalle = '',
    this.categoriaId,
    this.variedadId,
    this.tuesteId,
    this.procesoId,
    this.secadoId,
    this.notasSensoriales = const [],
    this.stockManual = false,
    this.moneda,
    this.loteVerdeId,
  });

  factory ProductoInfo.fromMap(Map<String, dynamic> m) => ProductoInfo(
        id: m['id']?.toString() ?? '',
        nombre: m['nombre']?.toString() ?? '',
        descripcionBreve: m['descripcionBreve']?.toString() ?? '',
        detalle: m['detalle']?.toString() ?? '',
        categoriaId: m['categoriaId']?.toString(),
        variedadId: m['variedadId']?.toString(),
        tuesteId: m['tuesteId']?.toString(),
        procesoId: m['procesoId']?.toString(),
        secadoId: m['secadoId']?.toString(),
        notasSensoriales: ((m['notasSensoriales'] as List?) ?? const []).map((e) => e.toString()).toList(),
        stockManual: m['stockManual'] == true,
        moneda: m['moneda']?.toString(),
        loteVerdeId: m['loteVerdeId']?.toString(),
      );
}

class ProductoInfoData {
  final ProductoInfo producto;
  final CatalogosProducto catalogos;
  const ProductoInfoData({required this.producto, required this.catalogos});

  factory ProductoInfoData.fromMap(Map<String, dynamic> m) => ProductoInfoData(
        producto: ProductoInfo.fromMap(Map<String, dynamic>.from(m['producto'] as Map)),
        catalogos: CatalogosProducto.fromMap(Map<String, dynamic>.from((m['catalogos'] as Map?) ?? const {})),
      );
}
