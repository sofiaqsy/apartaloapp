import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Servicio para manejar conversaciones en Firestore
class ConversationFirestoreService {
  // Singleton
  static final ConversationFirestoreService _instance = ConversationFirestoreService._internal();
  factory ConversationFirestoreService() => _instance;
  ConversationFirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== REFERENCIAS ====================

  /// Referencia a la colección de negocios
  CollectionReference get _negociosRef => _firestore.collection('negocios');

  /// Referencia a conversaciones de un negocio
  CollectionReference _conversacionesRef(String businessId) =>
      _negociosRef.doc(businessId).collection('conversaciones');

  /// Referencia a mensajes de una conversación
  CollectionReference _mensajesRef(String businessId, String whatsapp) =>
      _conversacionesRef(businessId).doc(whatsapp).collection('mensajes');

  // ==================== CONVERSACIONES ====================

  /// Obtener todas las conversaciones de un negocio
  Stream<List<Conversacion>> getConversaciones(String businessId) {
    return _conversacionesRef(businessId)
        .orderBy('ultimoMensaje', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Conversacion.fromFirestore(doc))
            .toList());
  }

  /// Obtener conversaciones en modo soporte/ayuda (requieren atención)
  Stream<List<Conversacion>> getConversacionesSoporte(String businessId) {
    return _conversacionesRef(businessId)
        .where('modo', whereIn: ['soporte', 'ayuda'])
        .orderBy('ultimoMensaje', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Conversacion.fromFirestore(doc))
            .toList());
  }

  /// Obtener conversaciones no leídas
  Stream<List<Conversacion>> getConversacionesNoLeidas(String businessId) {
    return _conversacionesRef(businessId)
        .where('noLeidos', isGreaterThan: 0)
        .orderBy('noLeidos', descending: true)
        .orderBy('ultimoMensaje', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Conversacion.fromFirestore(doc))
            .toList());
  }

  /// Obtener una conversación específica
  Stream<Conversacion?> getConversacion(String businessId, String whatsapp) {
    return _conversacionesRef(businessId)
        .doc(whatsapp)
        .snapshots()
        .map((doc) => doc.exists ? Conversacion.fromFirestore(doc) : null);
  }

  /// Crear o actualizar conversación
  Future<void> actualizarConversacion({
    required String businessId,
    required String whatsapp,
    String? nombre,
    String? modo,
    String? ultimoTexto,
    bool incrementarNoLeidos = false,
  }) async {
    final docRef = _conversacionesRef(businessId).doc(whatsapp);
    final doc = await docRef.get();

    if (doc.exists) {
      // Actualizar existente
      final updates = <String, dynamic>{
        'ultimoMensaje': FieldValue.serverTimestamp(),
      };
      if (nombre != null) updates['nombre'] = nombre;
      if (modo != null) updates['modo'] = modo;
      if (ultimoTexto != null) updates['ultimoTexto'] = ultimoTexto;
      if (incrementarNoLeidos) {
        updates['noLeidos'] = FieldValue.increment(1);
      }
      await docRef.update(updates);
    } else {
      // Crear nueva
      await docRef.set({
        'whatsapp': whatsapp,
        'nombre': nombre ?? whatsapp,
        'modo': modo ?? 'bot',
        'ultimoTexto': ultimoTexto ?? '',
        'ultimoMensaje': FieldValue.serverTimestamp(),
        'noLeidos': incrementarNoLeidos ? 1 : 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Marcar conversación como leída
  Future<void> marcarComoLeida(String businessId, String whatsapp) async {
    await _conversacionesRef(businessId).doc(whatsapp).update({
      'noLeidos': 0,
    });
  }

  /// Cambiar modo de conversación (bot, soporte, ayuda)
  Future<void> cambiarModo(String businessId, String whatsapp, String modo) async {
    await _conversacionesRef(businessId).doc(whatsapp).update({
      'modo': modo,
    });
  }

  // ==================== MENSAJES ====================

  /// Obtener mensajes de una conversación (en tiempo real)
  Stream<List<Mensaje>> getMensajes(String businessId, String whatsapp, {int limite = 50}) {
    return _mensajesRef(businessId, whatsapp)
        .orderBy('timestamp', descending: true)
        .limit(limite)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Mensaje.fromFirestore(doc))
            .toList()
            .reversed
            .toList()); // Revertir para mostrar más antiguos primero
  }

  /// Obtener mensajes paginados (para historial)
  Future<List<Mensaje>> getMensajesPaginados(
    String businessId,
    String whatsapp, {
    int limite = 20,
    DocumentSnapshot? ultimoDoc,
  }) async {
    Query query = _mensajesRef(businessId, whatsapp)
        .orderBy('timestamp', descending: true)
        .limit(limite);

    if (ultimoDoc != null) {
      query = query.startAfterDocument(ultimoDoc);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => Mensaje.fromFirestore(doc)).toList();
  }

  /// Enviar mensaje
  Future<void> enviarMensaje({
    required String businessId,
    required String whatsapp,
    required String texto,
    required String origen, // 'cliente', 'negocio', 'bot'
    String? tipo, // 'text', 'image', 'audio', 'document'
    String? mediaUrl,
    Map<String, dynamic>? metadata,
  }) async {
    // Agregar mensaje
    await _mensajesRef(businessId, whatsapp).add({
      'texto': texto,
      'origen': origen,
      'tipo': tipo ?? 'text',
      'mediaUrl': mediaUrl,
      'metadata': metadata,
      'timestamp': FieldValue.serverTimestamp(),
      'leido': origen == 'negocio' || origen == 'bot',
    });

    // Actualizar conversación
    await actualizarConversacion(
      businessId: businessId,
      whatsapp: whatsapp,
      ultimoTexto: texto,
      incrementarNoLeidos: origen == 'cliente',
    );
  }

  /// Marcar mensajes como leídos
  Future<void> marcarMensajesLeidos(String businessId, String whatsapp) async {
    final batch = _firestore.batch();
    
    final mensajesNoLeidos = await _mensajesRef(businessId, whatsapp)
        .where('leido', isEqualTo: false)
        .get();

    for (final doc in mensajesNoLeidos.docs) {
      batch.update(doc.reference, {'leido': true});
    }

    await batch.commit();
    await marcarComoLeida(businessId, whatsapp);
  }

  // ==================== ESTADÍSTICAS ====================

  /// Contar conversaciones en soporte
  Future<int> contarConversacionesSoporte(String businessId) async {
    final snapshot = await _conversacionesRef(businessId)
        .where('modo', whereIn: ['soporte', 'ayuda'])
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  /// Contar mensajes no leídos totales
  Future<int> contarMensajesNoLeidos(String businessId) async {
    final snapshot = await _conversacionesRef(businessId)
        .where('noLeidos', isGreaterThan: 0)
        .get();
    
    int total = 0;
    for (final doc in snapshot.docs) {
      total += (doc.data() as Map<String, dynamic>)['noLeidos'] as int? ?? 0;
    }
    return total;
  }

  // ==================== MIGRACIÓN DESDE SHEETS ====================

  /// Importar conversación desde datos de Sheets
  Future<void> importarConversacion({
    required String businessId,
    required String whatsapp,
    required String nombre,
    required List<Map<String, dynamic>> mensajes,
  }) async {
    try {
      // Crear conversación
      final ultimoMensaje = mensajes.isNotEmpty ? mensajes.last : null;
      await _conversacionesRef(businessId).doc(whatsapp).set({
        'whatsapp': whatsapp,
        'nombre': nombre,
        'modo': 'bot',
        'ultimoTexto': ultimoMensaje?['texto'] ?? '',
        'ultimoMensaje': ultimoMensaje?['timestamp'] ?? FieldValue.serverTimestamp(),
        'noLeidos': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'importadoDeSheets': true,
      });

      // Importar mensajes en batches (máximo 500 por batch)
      final batch = _firestore.batch();
      int count = 0;

      for (final mensaje in mensajes) {
        final docRef = _mensajesRef(businessId, whatsapp).doc();
        batch.set(docRef, {
          'texto': mensaje['texto'] ?? '',
          'origen': mensaje['origen'] ?? 'cliente',
          'tipo': mensaje['tipo'] ?? 'text',
          'mediaUrl': mensaje['mediaUrl'],
          'timestamp': mensaje['timestamp'] ?? FieldValue.serverTimestamp(),
          'leido': true,
          'importadoDeSheets': true,
        });

        count++;
        if (count >= 500) {
          await batch.commit();
          count = 0;
        }
      }

      if (count > 0) {
        await batch.commit();
      }

      debugPrint('✅ Importada conversación $whatsapp con ${mensajes.length} mensajes');
    } catch (e) {
      debugPrint('❌ Error importando conversación: $e');
      rethrow;
    }
  }
}

// ==================== MODELOS ====================

/// Modelo de Conversación
class Conversacion {
  final String whatsapp;
  final String nombre;
  final String modo; // 'bot', 'soporte', 'ayuda'
  final String ultimoTexto;
  final DateTime? ultimoMensaje;
  final int noLeidos;
  final DateTime? createdAt;

  Conversacion({
    required this.whatsapp,
    required this.nombre,
    required this.modo,
    required this.ultimoTexto,
    this.ultimoMensaje,
    required this.noLeidos,
    this.createdAt,
  });

  factory Conversacion.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Conversacion(
      whatsapp: data['whatsapp'] ?? doc.id,
      nombre: data['nombre'] ?? '',
      modo: data['modo'] ?? 'bot',
      ultimoTexto: data['ultimoTexto'] ?? '',
      ultimoMensaje: (data['ultimoMensaje'] as Timestamp?)?.toDate(),
      noLeidos: data['noLeidos'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get requiereAtencion => modo == 'soporte' || modo == 'ayuda';
  bool get tieneNoLeidos => noLeidos > 0;
}

/// Modelo de Mensaje
class Mensaje {
  final String id;
  final String texto;
  final String origen; // 'cliente', 'negocio', 'bot'
  final String tipo; // 'text', 'image', 'audio', 'document'
  final String? mediaUrl;
  final DateTime? timestamp;
  final bool leido;
  final Map<String, dynamic>? metadata;

  Mensaje({
    required this.id,
    required this.texto,
    required this.origen,
    required this.tipo,
    this.mediaUrl,
    this.timestamp,
    required this.leido,
    this.metadata,
  });

  factory Mensaje.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Mensaje(
      id: doc.id,
      texto: data['texto'] ?? '',
      origen: data['origen'] ?? 'cliente',
      tipo: data['tipo'] ?? 'text',
      mediaUrl: data['mediaUrl'],
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      leido: data['leido'] ?? false,
      metadata: data['metadata'],
    );
  }

  bool get esDelCliente => origen == 'cliente';
  bool get esDelNegocio => origen == 'negocio';
  bool get esDelBot => origen == 'bot';
  bool get tieneMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
}
