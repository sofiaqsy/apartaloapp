/// Modelos para conversaciones del bot WhatsApp

class BotConversation {
  final String id;
  final String fechaInicio;
  final String cliente;
  final String whatsapp;
  final String estado; // LISTENING, ACTIVA, CERRADA
  final String ultimaAct;
  final int vecesAtendida;
  final String? ultimaCierre;
  final String? ultimoMensaje;
  final bool pendienteRespuesta;
  final int mensajesSinResponder;
  final String? ultimoTipo;
  final bool solicitaAsesor;

  BotConversation({
    required this.id,
    required this.fechaInicio,
    required this.cliente,
    required this.whatsapp,
    required this.estado,
    required this.ultimaAct,
    this.vecesAtendida = 0,
    this.ultimaCierre,
    this.ultimoMensaje,
    this.pendienteRespuesta = false,
    this.mensajesSinResponder = 0,
    this.ultimoTipo,
    this.solicitaAsesor = false,
  });

  factory BotConversation.fromJson(Map<String, dynamic> json) {
    return BotConversation(
      id: json['id'] ?? '',
      fechaInicio: json['fechaInicio'] ?? '',
      cliente: json['cliente'] ?? 'Cliente',
      whatsapp: json['whatsapp'] ?? '',
      estado: json['estado'] ?? 'LISTENING',
      ultimaAct: json['ultimaAct'] ?? '',
      vecesAtendida: json['vecesAtendida'] ?? 0,
      ultimaCierre: json['ultimaCierre'],
      ultimoMensaje: json['ultimoMensaje'],
      pendienteRespuesta: json['pendienteRespuesta'] ?? false,
      mensajesSinResponder: json['mensajesSinResponder'] ?? 0,
      ultimoTipo: json['ultimoTipo'],
      solicitaAsesor: json['solicitaAsesor'] ?? (json['estado'] == 'ACTIVA'),
    );
  }

  bool get isActive => estado == 'ACTIVA' || estado == 'LISTENING';
  bool get isClosed => estado == 'CERRADA';
  bool get isListening => estado == 'LISTENING';
  bool get needsAttention => solicitaAsesor && pendienteRespuesta;
}

class BotMessage {
  final String id;
  final String conversacionId;
  final String timestamp;
  final String tipo; // CLIENTE, BOT, ASESOR, SISTEMA
  final String mensaje;
  final String? de;

  BotMessage({
    required this.id,
    required this.conversacionId,
    required this.timestamp,
    required this.tipo,
    required this.mensaje,
    this.de,
  });

  factory BotMessage.fromJson(Map<String, dynamic> json) {
    return BotMessage(
      id: json['id'] ?? '',
      conversacionId: json['conversacionId'] ?? '',
      timestamp: json['timestamp'] ?? '',
      tipo: json['tipo'] ?? 'CLIENTE',
      mensaje: json['mensaje'] ?? '',
      de: json['de'],
    );
  }

  bool get isFromClient => tipo == 'CLIENTE';
  bool get isFromBot => tipo == 'BOT';
  bool get isFromAdvisor => tipo == 'ASESOR';
  bool get isSystem => tipo == 'SISTEMA';

  DateTime? get dateTime {
    try {
      return DateTime.parse(timestamp);
    } catch (_) {
      return null;
    }
  }
}

class ClientePendiente {
  final String whatsapp;
  final String cliente;
  final String conversacionId;
  final String ultimaAct;
  final bool pendienteRespuesta;
  final int mensajesSinResponder;
  final String? ultimoMensaje;

  ClientePendiente({
    required this.whatsapp,
    required this.cliente,
    required this.conversacionId,
    required this.ultimaAct,
    this.pendienteRespuesta = false,
    this.mensajesSinResponder = 0,
    this.ultimoMensaje,
  });

  factory ClientePendiente.fromJson(Map<String, dynamic> json) {
    return ClientePendiente(
      whatsapp: json['whatsapp'] ?? '',
      cliente: json['cliente'] ?? 'Cliente',
      conversacionId: json['conversacionId'] ?? '',
      ultimaAct: json['ultimaAct'] ?? '',
      pendienteRespuesta: json['pendienteRespuesta'] ?? false,
      mensajesSinResponder: json['mensajesSinResponder'] ?? 0,
      ultimoMensaje: json['ultimoMensaje'],
    );
  }
}
