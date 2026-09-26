import '../models/models.dart';
import '../providers/app_provider.dart';

class FinanceBootstrapService {
  static const _names = <String, String>{
    'food_exp': 'Alimentação',
    'transport': 'Transporte',
    'shopping': 'Compras',
    'bills': 'Moradia & Contas',
    'health': 'Saúde',
    'entertainment': 'Lazer',
    'education': 'Educação',
    'other_exp': 'Outros',
    'salary': 'Salário',
    'freelance': 'Freelancer',
    'business': 'Negócios',
    'investment': 'Investimentos',
    'gift': 'Presentes',
  };

  static Future<void> apply(AppProvider app) async {
    for (final category in List<AppCategory>.from(app.categories)) {
      final desired = _names[category.id];
      if (desired == null || category.name == desired) continue;
      await app.updateCategory(
        category.copyWith(name: desired),
      );
    }
  }
}
