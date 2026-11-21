/// The look of GNOME applications (libadwaita), built from Flutter's own
/// widgets: its colours, a Material theme tuned to it, and the controls
/// Material has no close match for.
library;

import 'package:material_ui/material_ui.dart';

/// GNOME's interface font, then what other desktops ship.
const adwaitaFont = 'Adwaita Sans';
const adwaitaFontFallback = ['Cantarell', 'Inter', 'Ubuntu', 'Noto Sans', 'DejaVu Sans', 'Liberation Sans'];

/// libadwaita's named colours.
class Adwaita {
  const Adwaita(this.dark);
  Adwaita.of(BuildContext context) : dark = Theme.of(context).brightness == Brightness.dark;

  final bool dark;

  static const blue = Color(0xFF3584E4);

  Color get window => dark ? const Color(0xFF222226) : const Color(0xFFFAFAFB);
  Color get sidebar => dark ? const Color(0xFF2E2E32) : const Color(0xFFEBEBED);
  Color get card => dark ? const Color(0x14FFFFFF) : const Color(0xFFFFFFFF);
  Color get popover => dark ? const Color(0xFF36363A) : const Color(0xFFFFFFFF);

  /// Text and symbolic icons.
  Color get ink => dark ? const Color(0xFFFFFFFF) : const Color(0xCC000006);
  Color get _base => dark ? const Color(0xFFFFFFFF) : const Color(0xFF000006);

  /// The text colour at a fraction of its strength, for fills and lines.
  Color shade(double alpha) => _base.withValues(alpha: alpha * (dark ? 1 : 0.8));

  Color get dim => shade(0.55);
  Color get border => shade(0.15);
  Color get accent => blue;

  /// The accent as a text colour, readable on the window background.
  Color get accentText => dark ? const Color(0xFF81D0FF) : const Color(0xFF0461BE);
  Color get destructive => dark ? const Color(0xFFFF938C) : const Color(0xFFC30000);
}

/// A Material theme in which the stock widgets look at home on GNOME.
ThemeData adwaitaTheme(Brightness brightness) {
  final a = Adwaita(brightness == Brightness.dark);
  const white = Color(0xFFFFFFFF);
  final scheme = ColorScheme.fromSeed(seedColor: Adwaita.blue, brightness: brightness).copyWith(
    primary: a.accent,
    onPrimary: white,
    secondary: a.accent,
    onSecondary: white,
    surface: a.window,
    onSurface: a.ink,
    onSurfaceVariant: a.dim,
    surfaceContainerLowest: a.window,
    surfaceContainerLow: a.card,
    surfaceContainer: a.popover,
    surfaceContainerHigh: a.popover,
    surfaceContainerHighest: a.shade(0.1),
    outline: a.border,
    outlineVariant: a.shade(0.1),
    error: a.destructive,
    surfaceTint: Colors.transparent,
  );
  TextStyle text(double size, [FontWeight weight = FontWeight.w400]) => TextStyle(
    fontFamily: adwaitaFont,
    fontFamilyFallback: adwaitaFontFallback,
    fontSize: size,
    fontWeight: weight,
    color: a.ink,
    height: 1.3,
    letterSpacing: 0,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(9));
  final label = text(15, FontWeight.w700);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 9);

  /// A fill that reacts to the pointer the way GTK buttons do.
  WidgetStateProperty<Color?> fill(Color base, {required Color hover, required Color pressed}) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.pressed)
            ? pressed
            : states.contains(WidgetState.hovered)
            ? hover
            : base,
      );
  ButtonStyle button({required WidgetStateProperty<Color?> background, required Color foreground}) => ButtonStyle(
    backgroundColor: background,
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled) ? foreground.withValues(alpha: 0.5) : foreground,
    ),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: const WidgetStatePropertyAll(BorderSide.none),
    shape: WidgetStatePropertyAll(shape),
    padding: const WidgetStatePropertyAll(buttonPadding),
    minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
    textStyle: WidgetStatePropertyAll(label),
  );
  final regular = button(
    background: fill(a.shade(0.1), hover: a.shade(0.15), pressed: a.shade(0.3)),
    foreground: a.ink,
  );
  final flat = button(
    background: fill(Colors.transparent, hover: a.shade(0.07), pressed: a.shade(0.16)),
    foreground: a.ink,
  );
  final suggested = button(
    background: fill(
      a.accent,
      hover: Color.alphaBlend(white.withValues(alpha: 0.1), a.accent),
      pressed: Color.alphaBlend(const Color(0x33000000), a.accent),
    ),
    foreground: white,
  );
  OutlineInputBorder entry([BorderSide side = BorderSide.none]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: side);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: adwaitaFont,
    fontFamilyFallback: adwaitaFontFallback,
    scaffoldBackgroundColor: a.window,
    canvasColor: a.window,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: a.shade(0.07),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textTheme: TextTheme(
      titleLarge: text(20, FontWeight.w800),
      titleMedium: text(15, FontWeight.w700),
      titleSmall: text(15, FontWeight.w700),
      bodyLarge: text(15),
      bodyMedium: text(15),
      bodySmall: text(12).copyWith(color: a.dim),
      labelLarge: label,
      labelMedium: text(12),
      labelSmall: text(12),
    ),
    iconTheme: IconThemeData(color: a.ink, size: 16),
    dividerTheme: DividerThemeData(color: a.border, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(style: suggested),
    outlinedButtonTheme: OutlinedButtonThemeData(style: regular),
    elevatedButtonTheme: ElevatedButtonThemeData(style: regular),
    textButtonTheme: TextButtonThemeData(style: flat),
    iconButtonTheme: IconButtonThemeData(
      style: flat.copyWith(
        padding: const WidgetStatePropertyAll(EdgeInsets.all(9)),
        minimumSize: const WidgetStatePropertyAll(Size(34, 34)),
        iconSize: const WidgetStatePropertyAll(16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: a.shade(0.1),
      hoverColor: Colors.transparent,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      hintStyle: text(15).copyWith(color: a.dim),
      border: entry(),
      enabledBorder: entry(),
      focusedBorder: entry(BorderSide(color: a.accent.withValues(alpha: 0.5), width: 2)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: a.ink,
      selectionColor: a.accent.withValues(alpha: 0.3),
      selectionHandleColor: a.accent,
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: a.shade(0.3), width: 2),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? a.accent : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(white),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: a.shade(0.1),
      selectedColor: a.accent,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      labelStyle: text(14, FontWeight.w700),
      secondaryLabelStyle: text(14, FontWeight.w700).copyWith(color: white),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: const Color(0xE6000000), borderRadius: BorderRadius.circular(9)),
      textStyle: text(14).copyWith(color: white),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      waitDuration: const Duration(milliseconds: 500),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: a.popover,
      elevation: 6,
      shadowColor: const Color(0x66000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: a.shade(0.1)),
      ),
      textStyle: text(15),
      menuPadding: const EdgeInsets.all(6),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor: WidgetStatePropertyAll(a.shade(0.3)),
    ),
  );
}

/// GNOME's switch: a pill with a round knob.
class AdwSwitch extends StatelessWidget {
  const AdwSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final a = Adwaita.of(context);
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 46,
              height: 26,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? a.accent : a.shade(0.15),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// GNOME's drop-down: a button showing the choice, with a menu below it.
class AdwDropDown<T> extends StatelessWidget {
  const AdwDropDown({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final a = Adwaita.of(context);
    final text = Theme.of(context).textTheme.bodyMedium!;
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      tooltip: '',
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final e in options.entries)
          PopupMenuItem(
            value: e.key,
            height: 34,
            child: Row(
              children: [
                Expanded(child: Text(e.value, style: text)),
                if (e.key == value) Icon(Icons.check, size: 16, color: a.ink),
              ],
            ),
          ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(color: a.shade(0.1), borderRadius: BorderRadius.circular(9)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(options[value] ?? '', style: text),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down, size: 18, color: a.ink),
          ],
        ),
      ),
    );
  }
}

/// A group of rows on a card, GNOME's "boxed list".
BoxDecoration adwaitaCard(Adwaita a) => BoxDecoration(
  color: a.card,
  borderRadius: BorderRadius.circular(12),
  boxShadow: a.dark
      ? null
      : const [
          BoxShadow(color: Color(0x08000006), spreadRadius: 1),
          BoxShadow(color: Color(0x12000006), blurRadius: 3, spreadRadius: 1, offset: Offset(0, 1)),
        ],
);
