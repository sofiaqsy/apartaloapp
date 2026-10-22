/// Opción de un catálogo (categoría, variedad, tueste, proceso, secado).
class OpcionCatalogo {
  final String id;
  final String nombre;
  const OpcionCatalogo({required this.id, required this.nombre});

  factory OpcionCatalogo.fromMap(Map<String, dynamic> m) =>
      OpcionCatalogo(id: m['id']?.toString() ?? '', nombre: m['nombre']?.toString() ?? '');
}

/// Catálogos para los selectores de "Información general".
class CatalogosProducto {
  final List<OpcionCatalogo> categorias;
  final List<OpcionCatalogo> variedades;
  final List<OpcionCatalogo> tuestes;
  final List<OpcionCatalogo> procesos;
  final List<OpcionCatalogo> secados;
  final List<String> notasSugeridas;

  const CatalogosProducto({
    this.categorias = const [],
    this.variedades = const [],
    this.tuestes = const [],
    this.procesos = const [],
    this.secados = const [],
    this.notasSugeridas = const [],
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
