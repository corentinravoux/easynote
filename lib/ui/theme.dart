import 'package:flutter/material.dart';

/// The easynote look: ruled index cards on a cool desk.
///
/// A note is a white card with a crimson rule under its title and faint blue
/// ruled lines behind its items. Everything around the cards stays quiet.
@immutable
class Palette extends ThemeExtension<Palette> {
  /// Background behind the cards.
  final Color desk;
  final Color card;
  final Color ink;

  /// Secondary text: previews, counts, done items.
  final Color muted;

  /// The blue ruled lines of the card.
  final Color rule;

  /// The crimson rule under a card title; also the one accent colour.
  final Color accent;
  final Color border;

  /// Selected row in the folder tree, hovered card border.
  final Color highlight;

  /// E-ink: no animation, no translucency, no ripples.
  final bool flat;

  const Palette({
    required this.desk,
    required this.card,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.accent,
    required this.border,
    required this.highlight,
    this.flat = false,
  });

  static const light = Palette(
    desk: Color(0xFFEEF1F5),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF1F2A44),
    muted: Color(0xFF5E6A82),
    rule: Color(0xFFDCE5F2),
    accent: Color(0xFFC8344F),
    border: Color(0xFFD5DCE6),
    highlight: Color(0xFFDDE6F3),
  );

  static const dark = Palette(
    desk: Color(0xFF121827),
    card: Color(0xFF1B2336),
    ink: Color(0xFFE4E9F2),
    muted: Color(0xFF97A3BA),
    rule: Color(0xFF26324B),
    accent: Color(0xFFF06B84),
    border: Color(0xFF2C3954),
    highlight: Color(0xFF2A3755),
  );

  static const eink = Palette(
    desk: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF000000),
    muted: Color(0xFF000000),
    rule: Color(0xFFBDBDBD),
    accent: Color(0xFF000000),
    border: Color(0xFF000000),
    highlight: Color(0xFFDDDDDD),
    flat: true,
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension PaletteOf on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>()!;
}

/// Height of one ruled line. Card previews and editor rows snap to it.
const ruleHeight = 26.0;

const serif = 'Literata';
const sans = 'Atkinson';

TextStyle noteText(Palette p, {double size = 16, Color? color}) => TextStyle(
      fontFamily: serif,
      fontSize: size,
      height: ruleHeight / size,
      color: color ?? p.ink,
      fontVariations: const [FontVariation.weight(400)],
    );

TextStyle titleText(Palette p, {double size = 18}) => TextStyle(
      fontFamily: serif,
      fontSize: size,
      height: 1.25,
      color: p.ink,
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation.weight(620)],
    );

ThemeData buildTheme(Palette p, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: p.ink,
    brightness: brightness,
  ).copyWith(
    primary: p.ink,
    onPrimary: p.card,
    secondary: p.accent,
    surface: p.card,
    onSurface: p.ink,
    outline: p.border,
    error: p.flat ? p.ink : p.accent,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: sans,
    scaffoldBackgroundColor: p.desk,
    extensions: [p],
  );
  return base.copyWith(
    splashFactory: p.flat ? NoSplash.splashFactory : InkSparkle.splashFactory,
    highlightColor: p.flat ? Colors.transparent : null,
    hoverColor: p.highlight.withValues(alpha: 0.5),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.highlight,
      selectionHandleColor: p.accent,
    ),
    pageTransitionsTheme: p.flat
        ? const PageTransitionsTheme(builders: {
            TargetPlatform.android: _NoTransition(),
            TargetPlatform.linux: _NoTransition(),
          })
        : const PageTransitionsTheme(builders: {
            TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          }),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: p.card,
      hintStyle: TextStyle(color: p.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: p.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: p.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: p.ink, width: 1.5),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.ink,
      foregroundColor: p.card,
      elevation: p.flat ? 0 : 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.ink),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: p.flat ? BorderSide(color: p.ink) : BorderSide.none,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: p.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(fontFamily: sans, color: p.card),
      behavior: SnackBarBehavior.floating,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.card : p.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.ink : p.desk),
    ),
  );
}

class _NoTransition extends PageTransitionsBuilder {
  const _NoTransition();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
          Animation<double> a, Animation<double> b, Widget child) =>
      child;
}

/// Horizontal ruled lines every [ruleHeight], starting [top] pixels down.
class RuledPaper extends CustomPainter {
  final Color color;
  final double top;
  final double left;
  RuledPaper(this.color, {this.top = 0, this.left = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = top + ruleHeight - 0.5; y < size.height; y += ruleHeight) {
      canvas.drawLine(Offset(left, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(RuledPaper old) =>
      old.color != color || old.top != top || old.left != left;
}
