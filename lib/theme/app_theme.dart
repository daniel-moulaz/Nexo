// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'nexo_tokens.dart';

const Map<String, Color> kSeedColors = {
  'nexo': NexoBrand.tealDeep,
  'violet': Color(0xFF6750A4),
  'blue': Color(0xFF0061A4),
  'green': Color(0xFF386A1F),
  'rose': Color(0xFF9C4257),
  'amber': Color(0xFF785900),
  'teal': Color(0xFF006874),
  'orange': Color(0xFFBF360C),
  'indigo': Color(0xFF283593),
  'cyan': Color(0xFF00838F),
  'pink': Color(0xFFAD1457),
  'lime': Color(0xFF558B2F),
  'deep_purple': Color(0xFF4527A0),
  'crimson': Color(0xFFB71C1C),
  'midnight': Color(0xFF1A237E),
  'forest': Color(0xFF1B5E20),
  'mint': Color(0xFF00695C),
  'olive': Color(0xFF827717),
  'sage': Color(0xFF33691E),
  'sky': Color(0xFF0277BD),
  'navy': Color(0xFF0D47A1),
  'cobalt': Color(0xFF1565C0),
  'ocean': Color(0xFF006064),
  'coral': Color(0xFFD84315),
  'gold': Color(0xFFF9A825),
  'slate': Color(0xFF37474F),
  'magenta': Color(0xFF880E4F),
  'turquoise': Color(0xFF004D40),
  'brown': Color(0xFF4E342E),
  'lavender': Color(0xFF6A1B9A),
};

const Map<String, String> kSeedLabels = {
  'nexo': 'Nexo',
  'violet': 'Violeta',
  'blue': 'Azul',
  'green': 'Verde',
  'rose': 'Rosa',
  'amber': 'Âmbar',
  'teal': 'Verde-azulado',
  'orange': 'Laranja',
  'indigo': 'Índigo',
  'cyan': 'Ciano',
  'pink': 'Rosa forte',
  'lime': 'Lima',
  'deep_purple': 'Roxo profundo',
  'crimson': 'Carmesim',
  'midnight': 'Azul meia-noite',
  'forest': 'Verde floresta',
  'mint': 'Menta',
  'olive': 'Oliva',
  'sage': 'Sálvia',
  'sky': 'Azul céu',
  'navy': 'Azul-marinho',
  'cobalt': 'Cobalto',
  'ocean': 'Oceano',
  'coral': 'Coral',
  'gold': 'Dourado',
  'slate': 'Ardósia',
  'magenta': 'Magenta',
  'turquoise': 'Turquesa',
  'brown': 'Marrom',
  'lavender': 'Lavanda',
};

Color seedColor(String key) => kSeedColors[key] ?? NexoBrand.tealDeep;

const Map<String, String> kFonts = {
  'default': 'Inter (padrão do Nexo)',
  'plus_jakarta_sans': 'Plus Jakarta Sans',
  'dm_sans': 'DM Sans',
  'nunito_sans': 'Nunito Sans',
  'space_grotesk': 'Space Grotesk',
  'outfit': 'Outfit',
  'sora': 'Sora',
  'poppins': 'Poppins',
  'nunito': 'Nunito',
};

/// Ships inside the app (assets/fonts/Inter, SIL OFL): it works offline and
/// has a true Medium, which Segoe UI lacks. No weight above 700 exists in the
/// bundle; asking for one makes the engine smear a fake bold over the Bold.
const kBundledFont = 'Inter';

TextTheme _applyFont(String font, TextTheme base) {
  if (font == 'default' || font == 'inter') {
    return base.apply(fontFamily: kBundledFont);
  }
  switch (font) {
    case 'plus_jakarta_sans':
      return GoogleFonts.plusJakartaSansTextTheme(base);
    case 'dm_sans':
      return GoogleFonts.dmSansTextTheme(base);
    case 'nunito_sans':
      return GoogleFonts.nunitoSansTextTheme(base);
    case 'space_grotesk':
      return GoogleFonts.spaceGroteskTextTheme(base);
    case 'outfit':
      return GoogleFonts.outfitTextTheme(base);
    case 'sora':
      return GoogleFonts.soraTextTheme(base);
    case 'poppins':
      return GoogleFonts.poppinsTextTheme(base);
    case 'nunito':
      return GoogleFonts.nunitoTextTheme(base);
    default:
      return base.apply(fontFamily: kBundledFont);
  }
}

ThemeMode resolveThemeMode(String mode) {
  switch (mode) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

ThemeData buildTheme({
  required String seed,
  required bool dark,
  bool amoled = false,
  String appFont = 'default',
  ColorScheme? dynamicScheme,
}) {
  final ColorScheme base;
  if (dynamicScheme == null && seed == 'nexo') {
    return _base(_nexoScheme(dark, amoled), appFont);
  }
  if (dynamicScheme != null) {
    base = (dark && amoled)
        ? dynamicScheme.copyWith(
            surface: Colors.black,
            surfaceContainerLow: const Color(0xFF0A0A0A),
            surfaceContainer: const Color(0xFF111111),
            surfaceContainerHigh: const Color(0xFF1A1A1A),
            surfaceContainerHighest: const Color(0xFF222222),
          )
        : dynamicScheme;
  } else {
    final seedColor = kSeedColors[seed] ?? const Color(0xFF6750A4);
    final seeded = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    base = (dark && amoled)
        ? seeded.copyWith(
            surface: Colors.black,
            surfaceContainerLow: const Color(0xFF0A0A0A),
            surfaceContainer: const Color(0xFF111111),
            surfaceContainerHigh: const Color(0xFF1A1A1A),
            surfaceContainerHighest: const Color(0xFF222222),
          )
        : _layered(seeded, seedColor, dark);
  }
  return _base(base, appFont);
}

/// The ink and paper of the mark as surfaces in layers: depth comes from the
/// steps between them, not from shadows or outlines.
ColorScheme _nexoScheme(bool dark, bool amoled) {
  if (dark) {
    return ColorScheme(
      brightness: Brightness.dark,
      primary: NexoBrand.teal,
      onPrimary: const Color(0xFF04221D),
      primaryContainer: const Color(0xFF123B39),
      onPrimaryContainer: const Color(0xFFBFF5EA),
      secondary: NexoBrand.onInkMuted,
      onSecondary: NexoBrand.ink,
      secondaryContainer: NexoBrand.inkHigh,
      onSecondaryContainer: const Color(0xFFE2E8F0),
      tertiary: const Color(0xFF8AB4F8),
      onTertiary: NexoBrand.ink,
      tertiaryContainer: const Color(0xFF1E3350),
      onTertiaryContainer: const Color(0xFFD6E4FB),
      error: NexoTones.expenseOnInk,
      onError: const Color(0xFF3B0A14),
      errorContainer: const Color(0xFF4A1522),
      onErrorContainer: const Color(0xFFFFD9DF),
      surface: amoled ? Colors.black : NexoBrand.ink,
      onSurface: const Color(0xFFE8EDF3),
      onSurfaceVariant: NexoBrand.onInkMuted,
      surfaceContainerLowest: amoled ? Colors.black : const Color(0xFF0A0F18),
      surfaceContainerLow:
          amoled ? const Color(0xFF0D1119) : const Color(0xFF141C2A),
      surfaceContainer:
          amoled ? const Color(0xFF141A25) : const Color(0xFF1A2433),
      surfaceContainerHigh:
          amoled ? const Color(0xFF1B2331) : const Color(0xFF212D40),
      surfaceContainerHighest: const Color(0xFF2A384D),
      outline: const Color(0xFF64748B),
      outlineVariant: NexoBrand.inkLine,
      inverseSurface: const Color(0xFFE8EDF3),
      onInverseSurface: NexoBrand.ink,
      inversePrimary: NexoBrand.tealDeep,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
  }
  return const ColorScheme(
    brightness: Brightness.light,
    primary: NexoBrand.tealDeep,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFCCF3EC),
    onPrimaryContainer: Color(0xFF053B36),
    secondary: Color(0xFF475569),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE2E8F0),
    onSecondaryContainer: Color(0xFF1E293B),
    tertiary: Color(0xFF1D4E89),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFD6E4FB),
    onTertiaryContainer: Color(0xFF0F2A4A),
    error: Color(0xFFBE123C),
    onError: Colors.white,
    errorContainer: Color(0xFFFFE1E6),
    onErrorContainer: Color(0xFF5F0A20),
    surface: Color(0xFFF2F4F7),
    onSurface: Color(0xFF101826),
    onSurfaceVariant: Color(0xFF4B5768),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Color(0xFFE9EDF2),
    surfaceContainerHigh: Color(0xFFE2E7EE),
    surfaceContainerHighest: Color(0xFFD8DFE8),
    outline: Color(0xFF7C8899),
    outlineVariant: Color(0xFFD5DCE5),
    inverseSurface: NexoBrand.ink,
    onInverseSurface: NexoBrand.onInk,
    inversePrimary: NexoBrand.teal,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );
}

/// Calm, layered surfaces (ink-blue at night, paper by day) tinted with a
/// touch of the chosen color, so cards read as levels instead of flat grey.
ColorScheme _layered(ColorScheme cs, Color seed, bool dark) {
  Color tint(Color base, double amount) =>
      Color.alphaBlend(seed.withValues(alpha: amount), base);
  if (dark) {
    return cs.copyWith(
      surface: tint(const Color(0xFF0B0F15), .03),
      surfaceContainerLowest: tint(const Color(0xFF080B10), .02),
      surfaceContainerLow: tint(const Color(0xFF111720), .04),
      surfaceContainer: tint(const Color(0xFF151C26), .05),
      surfaceContainerHigh: tint(const Color(0xFF1B232F), .06),
      surfaceContainerHighest: tint(const Color(0xFF222B38), .07),
      outlineVariant: tint(const Color(0xFF2A3443), .06),
    );
  }
  return cs.copyWith(
    surface: tint(const Color(0xFFF4F6F9), .02),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: tint(const Color(0xFFF0F2F6), .03),
    surfaceContainerHigh: tint(const Color(0xFFE9EDF2), .04),
    surfaceContainerHighest: tint(const Color(0xFFE1E6ED), .05),
    outlineVariant: tint(const Color(0xFFD9DEE6), .04),
  );
}

/// The Windows type ramp under Material's names: 12/16, 14/20, 20/28, 28/36.
/// Regular for reading, semibold for titles, nothing under 12. Tracking stays
/// at zero: Material's values were tuned for Roboto.
///
/// No style here turns on tabular figures. In Inter they also widen the hyphen
/// by 41% ("Bem - vindo"), and any of these styles can hold a sentence. Amounts
/// in columns ask for [NexoTones.figures] where they are drawn.
TextTheme _typeRamp(TextTheme t) {
  TextStyle? ramp(TextStyle? s, double size, double line, FontWeight weight) =>
      s?.copyWith(
          fontSize: size,
          height: line / size,
          fontWeight: weight,
          letterSpacing: 0,
          fontFeatures: const []);
  const regular = FontWeight.w400;
  const medium = FontWeight.w500;
  const semibold = FontWeight.w600;
  return t.copyWith(
    displayLarge: ramp(t.displayLarge, 48, 56, semibold),
    displayMedium: ramp(t.displayMedium, 40, 52, semibold),
    displaySmall: ramp(t.displaySmall, 34, 44, semibold),
    headlineLarge: ramp(t.headlineLarge, 32, 40, FontWeight.w700),
    headlineMedium: ramp(t.headlineMedium, 28, 36, semibold),
    headlineSmall: ramp(t.headlineSmall, 24, 32, semibold),
    titleLarge: ramp(t.titleLarge, 20, 28, semibold),
    titleMedium: ramp(t.titleMedium, 16, 24, semibold),
    titleSmall: ramp(t.titleSmall, 14, 20, semibold),
    bodyLarge: ramp(t.bodyLarge, 16, 24, regular),
    bodyMedium: ramp(t.bodyMedium, 14, 20, regular),
    bodySmall: ramp(t.bodySmall, 12, 16, regular),
    labelLarge: ramp(t.labelLarge, 14, 20, medium),
    labelMedium: ramp(t.labelMedium, 12, 16, medium),
    labelSmall: ramp(t.labelSmall, 12, 16, medium),
  );
}

ThemeData _base(ColorScheme cs, String appFont) {
  final baseTextTheme = ThemeData(brightness: cs.brightness).textTheme;
  final fontTextTheme = _typeRamp(_applyFont(appFont, baseTextTheme));
  final darkTheme = cs.brightness == Brightness.dark;
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    textTheme: fontTextTheme,
    splashFactory: InkSparkle.constantTurbulenceSeedSplashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    scaffoldBackgroundColor: cs.surface,
    appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle:
            fontTextTheme.titleLarge?.copyWith(color: cs.onSurface)),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: cs.surface,
      indicatorColor: cs.primaryContainer,
      indicatorShape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final style = fontTextTheme.labelMedium ?? const TextStyle();
        return states.contains(WidgetState.selected)
            ? style.copyWith(fontWeight: FontWeight.w600, color: cs.primary)
            : style.copyWith(color: cs.onSurfaceVariant);
      }),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NexoRadius.card),
          side: darkTheme
              ? BorderSide.none
              : BorderSide(color: cs.outlineVariant.withValues(alpha: .7))),
      elevation: 0,
      color: cs.surfaceContainerLow,
    ),
    chipTheme: ChipThemeData(
      shape: StadiumBorder(side: BorderSide(color: cs.outlineVariant)),
      backgroundColor: cs.surfaceContainerLow,
      selectedColor: cs.primaryContainer,
      checkmarkColor: cs.onPrimaryContainer,
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(64, 48),
            textStyle:
                fontTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NexoRadius.field)))),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 48),
            side: BorderSide(color: cs.outline),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NexoRadius.field)))),
    segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
            visualDensity: VisualDensity.standard,
            minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
            side: WidgetStatePropertyAll(BorderSide(color: cs.outlineVariant)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(NexoRadius.field))),
            backgroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? cs.primaryContainer
                    : Colors.transparent),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.selected)
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant))),
    // 44 px on both devices: a Windows laptop can have a touch screen too.
    iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            visualDensity: VisualDensity.standard)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: cs.surfaceContainerHigh),
    bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
    dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: .5), space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkTheme ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexoRadius.field)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexoRadius.field),
          borderSide: BorderSide(color: cs.outlineVariant)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexoRadius.field),
          borderSide: BorderSide(color: cs.primary, width: 2)),
    ),
  );
}

class NexoRoute<T> extends MaterialPageRoute<T> {
  NexoRoute({required super.builder, super.settings});
}

class NexoSlideUpRoute<T> extends PageRouteBuilder<T> {
  NexoSlideUpRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        );
}

class CurrencyInfo {
  final String code, symbol, name;
  const CurrencyInfo(this.code, this.symbol, this.name);
}

const List<CurrencyInfo> kCurrencies = [
  CurrencyInfo('USD', r'$', 'Dólar americano'),
  CurrencyInfo('EUR', '€', 'Euro'),
  CurrencyInfo('GBP', '£', 'Libra esterlina'),
  CurrencyInfo('BRL', r'R$', 'Real brasileiro'),
  CurrencyInfo('CAD', r'C$', 'Dólar canadense'),
  CurrencyInfo('AUD', r'A$', 'Dólar australiano'),
  CurrencyInfo('EGP', 'EGP', 'Libra egípcia'),
  CurrencyInfo('SAR', 'SR', 'Rial saudita'),
  CurrencyInfo('AED', 'د.إ', 'Dirham dos Emirados'),
  CurrencyInfo('KWD', 'KD', 'Dinar kuwaitiano'),
  CurrencyInfo('QAR', 'QR', 'Rial catariano'),
  CurrencyInfo('BHD', 'BD', 'Dinar bareinita'),
  CurrencyInfo('OMR', 'OMR', 'Rial omanense'),
  CurrencyInfo('JOD', 'JD', 'Dinar jordaniano'),
  CurrencyInfo('MAD', 'MAD', 'Dirham marroquino'),
  CurrencyInfo('TND', 'DT', 'Dinar tunisiano'),
  CurrencyInfo('LYD', 'LD', 'Dinar líbio'),
  CurrencyInfo('DZD', 'DA', 'Dinar argelino'),
  CurrencyInfo('SDG', 'SDG', 'Libra sudanesa'),
  CurrencyInfo('NGN', '₦', 'Naira nigeriana'),
  CurrencyInfo('GHS', 'GH₵', 'Cedi ganês'),
  CurrencyInfo('KES', 'KSh', 'Xelim queniano'),
  CurrencyInfo('ZAR', 'R', 'Rand sul-africano'),
  CurrencyInfo('ETB', 'Br', 'Birr etíope'),
  CurrencyInfo('TZS', 'TSh', 'Xelim tanzaniano'),
  CurrencyInfo('UGX', 'USh', 'Xelim ugandense'),
  CurrencyInfo('RWF', 'RF', 'Franco ruandês'),
  CurrencyInfo('XOF', 'CFA', 'Franco CFA Ocidental'),
  CurrencyInfo('XAF', 'FCFA', 'Franco CFA Central'),
  CurrencyInfo('MZN', 'MT', 'Metical moçambicano'),
  CurrencyInfo('ZMW', 'ZK', 'Kwacha zambiano'),
  CurrencyInfo('JPY', '¥', 'Iene japonês'),
  CurrencyInfo('CNY', '¥', 'Yuan chinês'),
  CurrencyInfo('INR', '₹', 'Rupia indiana'),
  CurrencyInfo('KRW', '₩', 'Won sul-coreano'),
  CurrencyInfo('IDR', 'Rp', 'Rupia indonésia'),
  CurrencyInfo('MYR', 'RM', 'Ringgit malaio'),
  CurrencyInfo('SGD', r'S$', 'Dólar de Singapura'),
  CurrencyInfo('THB', '฿', 'Baht tailandês'),
  CurrencyInfo('VND', '₫', 'Dong vietnamita'),
  CurrencyInfo('PHP', '₱', 'Peso filipino'),
  CurrencyInfo('PKR', 'Rs', 'Rupia paquistanesa'),
  CurrencyInfo('BDT', '৳', 'Taka bengalês'),
  CurrencyInfo('LKR', 'Rs', 'Rupia do Sri Lanka'),
  CurrencyInfo('NPR', 'Rs', 'Rupia nepalesa'),
  CurrencyInfo('MMK', 'K', 'Kyat de Mianmar'),
  CurrencyInfo('TWD', r'NT$', 'Dólar taiwanês'),
  CurrencyInfo('HKD', r'HK$', 'Dólar de Hong Kong'),
  CurrencyInfo('ILS', '₪', 'Novo shekel israelense'),
  CurrencyInfo('TRY', '₺', 'Lira turca'),
  CurrencyInfo('CHF', 'Fr', 'Franco suíço'),
  CurrencyInfo('SEK', 'kr', 'Coroa sueca'),
  CurrencyInfo('NOK', 'kr', 'Coroa norueguesa'),
  CurrencyInfo('DKK', 'kr', 'Coroa dinamarquesa'),
  CurrencyInfo('PLN', 'zł', 'Złoty polonês'),
  CurrencyInfo('CZK', 'Kč', 'Coroa tcheca'),
  CurrencyInfo('HUF', 'Ft', 'Forint húngaro'),
  CurrencyInfo('RON', 'lei', 'Leu romeno'),
  CurrencyInfo('BGN', 'лв', 'Lev búlgaro'),
  CurrencyInfo('RUB', '₽', 'Rublo russo'),
  CurrencyInfo('UAH', '₴', 'Hryvnia ucraniana'),
  CurrencyInfo('GEL', '₾', 'Lari georgiano'),
];

CurrencyInfo currencyInfo(String code) => kCurrencies
    .firstWhere((c) => c.code == code, orElse: () => kCurrencies.first);

final Map<String, NumberFormat> _numberFormatCache = {};

String formatAmount(double amount, String code) {
  final info = currencyInfo(code);
  final cacheKey = '$code:${code == 'BRL' ? 'pt_BR' : 'default'}';
  final fmt = _numberFormatCache.putIfAbsent(
    cacheKey,
    () => NumberFormat.currency(
      locale: code == 'BRL' ? 'pt_BR' : null,
      // pt_BR already separates the symbol with a space; other locales don't.
      symbol: code == 'BRL' ? info.symbol : '${info.symbol} ',
      decimalDigits: 2,
    ),
  );
  return fmt.format(amount);
}
