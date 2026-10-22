import 'package:flutter/material.dart';
import '../theme/fincas_tokens.dart';

/// Shared Fincas components. Everything here reads [FincasColors], [FincasText],
/// [FincasSpacing] and [FincasRadii]; screens must not restyle these ad hoc.

// ── Buttons ────────────────────────────────────────────────────────────────

Widget _buttonChild(String label, bool loading, Color spinnerColor) {
  if (!loading) return Text(label, textAlign: TextAlign.center);
  return SizedBox(
    width: 22,
    height: 22,
    child: CircularProgressIndicator(strokeWidth: 2.5, color: spinnerColor),
  );
}

/// The main action of a screen (one per screen). Ink background, white text.
class FincasPrimaryButton extends StatelessWidget {
  const FincasPrimaryButton({super.key, required this.label, required this.onPressed, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: loading ? '$label, cargando' : label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: FincasSpacing.buttonHeight,
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: loading ? FincasColors.ink : null,
            disabledForegroundColor: loading ? FincasColors.textOnInk : null,
          ),
          child: _buttonChild(label, loading, FincasColors.textOnInk),
        ),
      ),
    );
  }
}

/// A supporting action: white surface, strong outline, ink text.
class FincasSecondaryButton extends StatelessWidget {
  const FincasSecondaryButton({super.key, required this.label, required this.onPressed, this.loading = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: loading ? '$label, cargando' : label,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: FincasSpacing.buttonHeight,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          child: _buttonChild(label, loading, FincasColors.ink),
        ),
      ),
    );
  }
}

/// A low-emphasis action (back, skip, use another account). Espresso text, no outline.
class FincasTextButton extends StatelessWidget {
  const FincasTextButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(child: TextButton(onPressed: onPressed, child: Text(label)));
  }
}

// ── Surfaces ───────────────────────────────────────────────────────────────

enum FincasTone { neutral, success, warning, error }

Color _toneFg(FincasTone t) => switch (t) {
      FincasTone.success => FincasColors.success,
      FincasTone.warning => FincasColors.warning,
      FincasTone.error => FincasColors.error,
      FincasTone.neutral => FincasColors.textSecondary,
    };

Color _toneBg(FincasTone t) => switch (t) {
      FincasTone.success => FincasColors.successBg,
      FincasTone.warning => FincasColors.warningBg,
      FincasTone.error => FincasColors.errorBg,
      FincasTone.neutral => FincasColors.sand,
    };

/// Bordered surface (no shadow). Tappable when [onTap] is given.
class FincasCard extends StatelessWidget {
  const FincasCard({super.key, required this.child, this.onTap, this.tone});
  final Widget child;
  final VoidCallback? onTap;

  /// Optional tonal background for notices (for example a request in review).
  final FincasTone? tone;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(FincasRadii.large);
    return Material(
      color: tone == null ? FincasColors.surface : _toneBg(tone!),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: tone == null ? FincasColors.border : _toneBg(tone!)),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(FincasSpacing.cardPadding), child: child),
      ),
    );
  }
}

/// Small status label, for example the role or "En revisión".
class FincasStatusBadge extends StatelessWidget {
  const FincasStatusBadge(this.label, {super.key, this.tone = FincasTone.neutral});
  final String label;
  final FincasTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _toneBg(tone), borderRadius: BorderRadius.circular(FincasRadii.small)),
      child: Text(label, style: FincasText.caption.copyWith(color: _toneFg(tone), fontWeight: FontWeight.w600)),
    );
  }
}

/// A business of the account: the name leads, then location and role, then the entry action.
class FincasBusinessCard extends StatelessWidget {
  const FincasBusinessCard({
    super.key,
    required this.name,
    required this.onTap,
    this.city = '',
    this.roleLabel = '',
    this.isCurrent = false,
  });
  final String name;
  final String city;
  final String roleLabel;
  final bool isCurrent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3;
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, style: FincasText.sectionTitle),
        if (city.isNotEmpty) ...[
          const SizedBox(height: FincasSpacing.xs),
          Text(city, maxLines: 2, overflow: TextOverflow.ellipsis, style: FincasText.metadata),
        ],
        if (roleLabel.isNotEmpty || isCurrent) ...[
          const SizedBox(height: FincasSpacing.s),
          Wrap(
            spacing: FincasSpacing.s,
            runSpacing: FincasSpacing.xs,
            children: [
              if (roleLabel.isNotEmpty) FincasStatusBadge(roleLabel),
              if (isCurrent) const FincasStatusBadge('Abierto ahora', tone: FincasTone.success),
            ],
          ),
        ],
      ],
    );
    final action = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Entrar', style: FincasText.label.copyWith(color: FincasColors.espresso, fontWeight: FontWeight.w600)),
        const SizedBox(width: FincasSpacing.xs),
        const Icon(Icons.chevron_right, size: FincasIcons.regular, color: FincasColors.espresso),
      ],
    );
    return Semantics(
      button: true,
      label: 'Entrar a $name${city.isNotEmpty ? ', $city' : ''}${roleLabel.isNotEmpty ? ', $roleLabel' : ''}',
      excludeSemantics: true,
      child: FincasCard(
        onTap: onTap,
        // With large accessibility text the action moves under the details so the name keeps its width.
        child: largeText
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [details, const SizedBox(height: FincasSpacing.m), Align(alignment: Alignment.centerRight, child: action)],
              )
            : Row(
                children: [Expanded(child: details), const SizedBox(width: FincasSpacing.m), action],
              ),
      ),
    );
  }
}

class FincasSectionHeader extends StatelessWidget {
  const FincasSectionHeader(this.title, {super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.m),
      child: Semantics(header: true, child: Text(title, style: FincasText.sectionTitle)),
    );
  }
}

// ── Brand, loading, states ─────────────────────────────────────────────────

/// The FI logo (original asset, never redrawn) with the "Fincas" wordmark and tagline.
class FincasBrandMark extends StatelessWidget {
  const FincasBrandMark({super.key, this.logoSize = 96, this.showTagline = true});
  final double logoSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Fincas. Gestiona tu negocio fácilmente',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.24),
            child: Image.asset('assets/splash/splash.png', width: logoSize, height: logoSize, fit: BoxFit.cover),
          ),
          const SizedBox(height: FincasSpacing.xl),
          const Text('Fincas', style: FincasText.displayLarge),
          if (showTagline) ...[
            const SizedBox(height: FincasSpacing.s),
            const Text('Gestiona tu negocio fácilmente', textAlign: TextAlign.center, style: FincasText.bodySecondary),
          ],
        ],
      ),
    );
  }
}

/// Single loading indicator with an optional message. Use it instead of several spinners.
class FincasLoader extends StatelessWidget {
  const FincasLoader({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message ?? 'Cargando',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (message != null) ...[
            const SizedBox(height: FincasSpacing.m),
            Text(message!, textAlign: TextAlign.center, style: FincasText.bodySecondary),
          ],
        ],
      ),
    );
  }
}

/// Empty, status or error state: a title, a short explanation and an optional action.
class FincasMessageState extends StatelessWidget {
  const FincasMessageState({super.key, required this.title, required this.message, this.tone = FincasTone.neutral});
  final String title;
  final String message;
  final FincasTone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(title,
              textAlign: TextAlign.center,
              style: FincasText.sectionTitle.copyWith(color: tone == FincasTone.error ? FincasColors.error : FincasColors.textPrimary)),
        ),
        const SizedBox(height: FincasSpacing.s),
        Text(message, textAlign: TextAlign.center, style: FincasText.bodySecondary),
      ],
    );
  }
}
