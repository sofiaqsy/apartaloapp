import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Botón flotante de voz GRANDE para personas mayores
class VoiceButton extends StatelessWidget {
  final bool isListening;
  final bool isProcessing;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  const VoiceButton({
    super.key,
    required this.isListening,
    required this.isProcessing,
    required this.onPressed,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      onLongPress: onLongPress,
      child: Container(
        width: 88, // Más grande para personas mayores
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isListening
                ? [Colors.red.shade400, Colors.red.shade700]
                : isProcessing
                    ? [Colors.orange.shade400, Colors.orange.shade700]
                    : [Colors.blue.shade400, Colors.blue.shade700],
          ),
          boxShadow: [
            BoxShadow(
              color: (isListening 
                  ? Colors.red 
                  : isProcessing 
                      ? Colors.orange 
                      : Colors.blue).withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: isProcessing
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
              : Icon(
                  isListening ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 40, // Icono más grande
                ),
        ),
      )
          .animate(target: isListening ? 1 : 0)
          .scale(
            begin: const Offset(1, 1),
            end: const Offset(1.15, 1.15),
            duration: 600.ms,
            curve: Curves.easeInOut,
          )
          .then()
          .scale(
            begin: const Offset(1.15, 1.15),
            end: const Offset(1, 1),
            duration: 600.ms,
            curve: Curves.easeInOut,
          ),
    );
  }
}

/// Indicador de escucha con ondas - Más visible
class ListeningIndicator extends StatelessWidget {
  final bool isListening;
  final String? partialText;

  const ListeningIndicator({
    super.key,
    required this.isListening,
    this.partialText,
  });

  @override
  Widget build(BuildContext context) {
    if (!isListening && (partialText == null || partialText!.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.15),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: Colors.blue.shade100,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isListening)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hearing, color: Colors.blue.shade600, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Escuchando...',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                // Ondas de audio
                ...List.generate(4, (index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                      .animate(
                        onPlay: (controller) => controller.repeat(reverse: true),
                      )
                      .scaleY(
                        begin: 0.3,
                        end: 1.0,
                        delay: Duration(milliseconds: index * 120),
                        duration: 400.ms,
                      );
                }),
              ],
            ),
          if (partialText != null && partialText!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '"$partialText"',
                style: TextStyle(
                  fontSize: 18, // Texto más grande
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

/// Burbuja de mensaje del asistente - Más legible
class AssistantBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const AssistantBubble({
    super.key,
    required this.message,
    this.isUser = false,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue.shade500 : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Indicador de quién habla
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.smart_toy_rounded,
                        size: 16,
                        color: Colors.blue.shade600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Asistente',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              message,
              style: TextStyle(
                fontSize: 16, // Texto más grande para legibilidad
                color: isUser ? Colors.white : Colors.grey.shade800,
                height: 1.4,
              ),
            ),
            // Botones de confirmación
            if (onConfirm != null || onCancel != null) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onCancel != null)
                    OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('No', style: TextStyle(fontSize: 15)),
                    ),
                  if (onCancel != null) const SizedBox(width: 12),
                  if (onConfirm != null)
                    ElevatedButton.icon(
                      onPressed: onConfirm,
                      icon: const Icon(Icons.check, size: 20),
                      label: const Text('Sí', style: TextStyle(fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.15, end: 0);
  }
}

/// Chip de sugerencia de comando
class SuggestionChip extends StatelessWidget {
  final String text;
  final IconData icon;
  final VoidCallback onTap;

  const SuggestionChip({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.blue.shade600),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget de sugerencias rápidas
class QuickSuggestions extends StatelessWidget {
  final Function(String) onSuggestionTap;

  const QuickSuggestions({
    super.key,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      {'text': 'Productos', 'icon': Icons.inventory_2},
      {'text': 'Clientes', 'icon': Icons.people},
      {'text': 'Ayuda', 'icon': Icons.help},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: suggestions.map((s) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SuggestionChip(
              text: s['text'] as String,
              icon: s['icon'] as IconData,
              onTap: () => onSuggestionTap(s['text'] as String),
            ),
          );
        }).toList(),
      ),
    );
  }
}
