// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

const Map<String, Color> kSeedColors = {
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

Color seedColor(String key) => kSeedColors[key] ?? const Color(0xFF6750A4);

const Map<String, String> kFonts = {
  'default': 'Padrão do sistema',
  'plus_jakarta_sans': 'Plus Jakarta Sans',
  'dm_sans': 'DM Sans',
  'inter': 'Inter',
  'nunito_sans': 'Nunito Sans',
  'space_grotesk': 'Space Grotesk',
  'outfit': 'Outfit',
  'sora': 'Sora',
  'poppins': 'Poppins',
  'nunito': 'Nunito',
};

TextTheme _applyFont(String font, TextTheme base) {
  switch (font) {
    case 'plus_jakarta_sans':
      return GoogleFonts.plusJakartaSansTextTheme(base);
    case 'dm_sans':
      return GoogleFonts.dmSansTextTheme(base);
    case 'inter':
      return GoogleFonts.interTextTheme(base);
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
      return base;
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
        : seeded;
  }
  return _base(base, appFont);
}

ThemeData _base(ColorScheme cs, String appFont) {
  final baseTextTheme = ThemeData(brightness: cs.brightness).textTheme;
  final fontTextTheme = _applyFont(appFont, baseTextTheme);
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    textTheme: fontTextTheme,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final style = fontTextTheme.labelMedium ?? const TextStyle();
        if (states.contains(WidgetState.selected)) {
          return style.copyWith(
              fontSize: (style.fontSize ?? 12) - 1,
              fontWeight: FontWeight.bold);
        }
        return style.copyWith(fontSize: (style.fontSize ?? 12) - 1);
      }),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2)),
    ),
  );
}

class ExpensyRoute<T> extends MaterialPageRoute<T> {
  ExpensyRoute({required super.builder, super.settings});
}

class ExpensySlideUpRoute<T> extends PageRouteBuilder<T> {
  ExpensySlideUpRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
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
      symbol: '${info.symbol} ',
      decimalDigits: 2,
    ),
  );
  return fmt.format(amount);
}
