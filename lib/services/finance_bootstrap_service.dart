import '../models/models.dart';
import '../providers/app_provider.dart';

class FinanceBootstrapService {
  static const _names = <String, (String original, String pt)> {
    'food_exp': ('Food & Dining', 'Alimentação'),
    'transport': ('Transport', 'Transporte'),
    'shopping': ('Shopping', 'Compras'),
    'bills': ('Bills & Utilities', 'Moradia & Contas'),
    'health': ('Health', 'Saúde'),
    'entertainment': ('Entertainment', 'Lazer'),
    'education': ('Education', 'Educação'),
    'other_exp': ('Other', 'Outros'),
    'salary': ('Salary', 'Salário'),
    'freelance': ('Freelance', 'Freelancer'),
    'business': ('Business', 'Negócios'),
    'investment': ('Investment', 'Investimentos'),
    'gift': ('Gift', 'Presentes'),
  };

  static Future<void> apply(AppProvider app) async {
    for (final category in List<AppCategory>.from(app.categories)) {
      final pair = _names[category.id];
      if (pair == null) continue;
      final original = pair.$1;
      final desired = pair.$2;
      if (category.name != original) continue;
      await app.updateCategory(category.copyWith(name: desired));
    }
  }
}
