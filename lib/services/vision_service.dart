import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Modelo para el producto detectado
class ProductoDetectado {
  final String? nombre;
  final String? marca;
  final String? peso;
  final String? codigoBarras;
  final String? categoria;
  final String? descripcion;
  final String? confianza;
  final String? imagenUrl;

  ProductoDetectado({
    this.nombre,
    this.marca,
    this.peso,
    this.codigoBarras,
    this.categoria,
    this.descripcion,
    this.confianza,
    this.imagenUrl,
  });

  factory ProductoDetectado.fromJson(Map<String, dynamic> json) {
    return ProductoDetectado(
      nombre: json['nombre'] as String?,
      marca: json['marca'] as String?,
      peso: json['peso'] as String?,
      codigoBarras: json['codigo_barras'] as String?,
      categoria: json['categoria'] as String?,
      descripcion: json['descripcion'] as String?,
      confianza: json['confianza'] as String?,
      imagenUrl: json['imagen_url'] as String?,
    );
  }

  String get nombreCompleto {
    final partes = <String>[];
    if (marca != null && marca!.isNotEmpty) partes.add(marca!);
    if (nombre != null && nombre!.isNotEmpty) {
      if (marca == null || !nombre!.toLowerCase().contains(marca!.toLowerCase())) {
        partes.add(nombre!);
      } else {
        return nombre!;
      }
    }
    if (peso != null && peso!.isNotEmpty && (nombre == null || !nombre!.contains(peso!))) {
      partes.add(peso!);
    }
    return partes.join(' ').trim();
  }

  @override
  String toString() => 'ProductoDetectado(nombre: $nombre, marca: $marca, peso: $peso, codigo: $codigoBarras)';
}

/// Servicio para identificar productos
class VisionService {
  
  // ============ OPCIÓN 1: BUSCAR POR CÓDIGO DE BARRAS (GRATIS, SIN LÍMITES) ============
  
  /// Buscar producto en Open Food Facts por código de barras
  static Future<ProductoDetectado?> buscarPorCodigoBarras(String codigo) async {
    debugPrint('🔍 Buscando código: $codigo en Open Food Facts...');
    
    try {
      // Open Food Facts API (gratis, sin límites)
      final response = await http.get(
        Uri.parse('https://world.openfoodfacts.org/api/v2/product/$codigo.json'),
        headers: {'User-Agent': 'Fincas App - Flutter'},
      ).timeout(const Duration(seconds: 10));

      debugPrint('📡 Open Food Facts: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          
          final resultado = ProductoDetectado(
            nombre: product['product_name'] ?? product['product_name_es'] ?? product['generic_name'],
            marca: product['brands'],
            peso: product['quantity'],
            codigoBarras: codigo,
            categoria: _extraerCategoria(product['categories_tags']),
            descripcion: product['generic_name_es'] ?? product['generic_name'],
            confianza: 'alta',
            imagenUrl: product['image_url'] ?? product['image_front_url'],
          );
          
          debugPrint('✅ Producto encontrado: ${resultado.nombreCompleto}');
          return resultado;
        }
      }
      
      // Si no está en Open Food Facts, intentar UPC Database
      return await _buscarEnUPCDatabase(codigo);
      
    } catch (e) {
      debugPrint('❌ Error buscando código: $e');
    }
    
    return null;
  }

  /// Buscar en UPC Database (backup)
  static Future<ProductoDetectado?> _buscarEnUPCDatabase(String codigo) async {
    debugPrint('🔍 Buscando en UPC Database...');
    
    try {
      final response = await http.get(
        Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$codigo'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['items'] != null && (data['items'] as List).isNotEmpty) {
          final item = data['items'][0];
          
          return ProductoDetectado(
            nombre: item['title'],
            marca: item['brand'],
            peso: item['weight'],
            codigoBarras: codigo,
            categoria: item['category'],
            confianza: 'media',
            imagenUrl: (item['images'] as List?)?.firstOrNull,
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ UPC Database no disponible: $e');
    }
    
    return null;
  }

  static String? _extraerCategoria(dynamic categoriesTags) {
    if (categoriesTags == null) return null;
    if (categoriesTags is List && categoriesTags.isNotEmpty) {
      // Tomar la categoría más específica (última)
      final cat = categoriesTags.last.toString();
      // Limpiar formato "en:category-name"
      return cat.split(':').last.replaceAll('-', ' ').trim();
    }
    return null;
  }

  // ============ OPCIÓN 2: ANALIZAR IMAGEN CON IA (USA TOKENS) ============
  
  /// Analizar imagen con Gemini Vision (solo si es necesario)
  static Future<ProductoDetectado?> analizarImagenProducto(File imagen) async {
    final apiKey = AppConfig.geminiApiKey;
    
    if (apiKey.isEmpty) {
      debugPrint('❌ No hay API key de Gemini');
      return null;
    }

    try {
      final bytes = await imagen.readAsBytes();
      final base64Image = base64Encode(bytes);
      
      final extension = imagen.path.split('.').last.toLowerCase();
      String mimeType = 'image/jpeg';
      if (extension == 'png') mimeType = 'image/png';
      if (extension == 'webp') mimeType = 'image/webp';

      debugPrint('📸 Analizando imagen con Gemini Vision...');
      final startTime = DateTime.now();

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'text': '''Analiza esta imagen de un producto. Responde SOLO JSON:
{"nombre":"nombre del producto","marca":"marca","peso":"peso/cantidad","categoria":"categoría","codigo_barras":"código si es visible"}
Si no ves algo, pon null. Si no es producto: {"error":"No es un producto"}'''
                },
                {
                  'inline_data': {
                    'mime_type': mimeType,
                    'data': base64Image,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 200,
          },
        }),
      ).timeout(const Duration(seconds: 20));

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('📡 Gemini Vision: ${response.statusCode} (${elapsed}ms)');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        
        debugPrint('📝 Respuesta: $text');

        final jsonString = _extractJson(text);
        if (jsonString != null) {
          final resultado = jsonDecode(jsonString) as Map<String, dynamic>;
          if (resultado.containsKey('error')) return null;
          
          resultado['confianza'] = 'media';
          return ProductoDetectado.fromJson(resultado);
        }
      } else if (response.statusCode == 429) {
        debugPrint('⚠️ Cuota de Gemini agotada');
      }
    } catch (e) {
      debugPrint('❌ Error analizando imagen: $e');
    }

    return null;
  }

  static String? _extractJson(String text) {
    var clean = text.replaceAll(RegExp(r'```json\s*'), '').replaceAll(RegExp(r'```\s*'), '').trim();
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(clean);
    return match?.group(0);
  }
}
