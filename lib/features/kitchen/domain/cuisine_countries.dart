/// Кухни и страны происхождения блюд для рецептов HAN Eat.
class RecipeOriginCountry {
  const RecipeOriginCountry({
    required this.code,
    required this.nameRu,
    this.nameEn = '',
    this.flag = '',
  });

  /// ISO 3166-1 alpha-2
  final String code;
  final String nameRu;
  final String nameEn;
  final String flag;

  String get displayLabel => flag.isNotEmpty ? '$flag $nameRu' : nameRu;
}

/// Популярные страны/кухни для выбора при публикации рецепта.
const List<RecipeOriginCountry> kRecipeOriginCountries = [
  RecipeOriginCountry(
      code: 'RU', nameRu: 'Россия', nameEn: 'Russia', flag: '🇷🇺'),
  RecipeOriginCountry(
      code: 'IT', nameRu: 'Италия', nameEn: 'Italy', flag: '🇮🇹'),
  RecipeOriginCountry(
      code: 'FR', nameRu: 'Франция', nameEn: 'France', flag: '🇫🇷'),
  RecipeOriginCountry(
      code: 'ES', nameRu: 'Испания', nameEn: 'Spain', flag: '🇪🇸'),
  RecipeOriginCountry(
      code: 'DE', nameRu: 'Германия', nameEn: 'Germany', flag: '🇩🇪'),
  RecipeOriginCountry(
      code: 'GR', nameRu: 'Греция', nameEn: 'Greece', flag: '🇬🇷'),
  RecipeOriginCountry(
      code: 'TR', nameRu: 'Турция', nameEn: 'Turkey', flag: '🇹🇷'),
  RecipeOriginCountry(
      code: 'GE', nameRu: 'Грузия', nameEn: 'Georgia', flag: '🇬🇪'),
  RecipeOriginCountry(
      code: 'AM', nameRu: 'Армения', nameEn: 'Armenia', flag: '🇦🇲'),
  RecipeOriginCountry(
      code: 'AZ', nameRu: 'Азербайджан', nameEn: 'Azerbaijan', flag: '🇦🇿'),
  RecipeOriginCountry(
      code: 'UA', nameRu: 'Украина', nameEn: 'Ukraine', flag: '🇺🇦'),
  RecipeOriginCountry(
      code: 'BY', nameRu: 'Беларусь', nameEn: 'Belarus', flag: '🇧🇾'),
  RecipeOriginCountry(
      code: 'KZ', nameRu: 'Казахстан', nameEn: 'Kazakhstan', flag: '🇰🇿'),
  RecipeOriginCountry(
      code: 'UZ', nameRu: 'Узбекистан', nameEn: 'Uzbekistan', flag: '🇺🇿'),
  RecipeOriginCountry(
      code: 'CN', nameRu: 'Китай', nameEn: 'China', flag: '🇨🇳'),
  RecipeOriginCountry(
      code: 'JP', nameRu: 'Япония', nameEn: 'Japan', flag: '🇯🇵'),
  RecipeOriginCountry(
      code: 'KR', nameRu: 'Корея', nameEn: 'South Korea', flag: '🇰🇷'),
  RecipeOriginCountry(
      code: 'TH', nameRu: 'Таиланд', nameEn: 'Thailand', flag: '🇹🇭'),
  RecipeOriginCountry(
      code: 'VN', nameRu: 'Вьетнам', nameEn: 'Vietnam', flag: '🇻🇳'),
  RecipeOriginCountry(
      code: 'IN', nameRu: 'Индия', nameEn: 'India', flag: '🇮🇳'),
  RecipeOriginCountry(
      code: 'US', nameRu: 'США', nameEn: 'United States', flag: '🇺🇸'),
  RecipeOriginCountry(
      code: 'MX', nameRu: 'Мексика', nameEn: 'Mexico', flag: '🇲🇽'),
  RecipeOriginCountry(
      code: 'BR', nameRu: 'Бразилия', nameEn: 'Brazil', flag: '🇧🇷'),
  RecipeOriginCountry(
      code: 'AR', nameRu: 'Аргентина', nameEn: 'Argentina', flag: '🇦🇷'),
  RecipeOriginCountry(
      code: 'GB',
      nameRu: 'Великобритания',
      nameEn: 'United Kingdom',
      flag: '🇬🇧'),
  RecipeOriginCountry(
      code: 'IL', nameRu: 'Израиль', nameEn: 'Israel', flag: '🇮🇱'),
  RecipeOriginCountry(
      code: 'LB', nameRu: 'Ливан', nameEn: 'Lebanon', flag: '🇱🇧'),
  RecipeOriginCountry(
      code: 'MA', nameRu: 'Марокко', nameEn: 'Morocco', flag: '🇲🇦'),
  RecipeOriginCountry(
      code: 'EG', nameRu: 'Египет', nameEn: 'Egypt', flag: '🇪🇬'),
  RecipeOriginCountry(
      code: 'CA', nameRu: 'Канада', nameEn: 'Canada', flag: '🇨🇦'),
  RecipeOriginCountry(
      code: 'AU', nameRu: 'Австралия', nameEn: 'Australia', flag: '🇦🇺'),
  RecipeOriginCountry(
      code: 'PL', nameRu: 'Польша', nameEn: 'Poland', flag: '🇵🇱'),
  RecipeOriginCountry(
      code: 'CZ', nameRu: 'Чехия', nameEn: 'Czechia', flag: '🇨🇿'),
  RecipeOriginCountry(
      code: 'HU', nameRu: 'Венгрия', nameEn: 'Hungary', flag: '🇭🇺'),
  RecipeOriginCountry(
      code: 'RO', nameRu: 'Румыния', nameEn: 'Romania', flag: '🇷🇴'),
  RecipeOriginCountry(
      code: 'BG', nameRu: 'Болгария', nameEn: 'Bulgaria', flag: '🇧🇬'),
  RecipeOriginCountry(
      code: 'RS', nameRu: 'Сербия', nameEn: 'Serbia', flag: '🇷🇸'),
  RecipeOriginCountry(
      code: 'MD', nameRu: 'Молдова', nameEn: 'Moldova', flag: '🇲🇩'),
  RecipeOriginCountry(
      code: 'LT', nameRu: 'Литва', nameEn: 'Lithuania', flag: '🇱🇹'),
  RecipeOriginCountry(
      code: 'LV', nameRu: 'Латвия', nameEn: 'Latvia', flag: '🇱🇻'),
  RecipeOriginCountry(
      code: 'EE', nameRu: 'Эстония', nameEn: 'Estonia', flag: '🇪🇪'),
  RecipeOriginCountry(
      code: 'FI', nameRu: 'Финляндия', nameEn: 'Finland', flag: '🇫🇮'),
  RecipeOriginCountry(
      code: 'SE', nameRu: 'Швеция', nameEn: 'Sweden', flag: '🇸🇪'),
  RecipeOriginCountry(
      code: 'NO', nameRu: 'Норвегия', nameEn: 'Norway', flag: '🇳🇴'),
  RecipeOriginCountry(
      code: 'NL', nameRu: 'Нидерланды', nameEn: 'Netherlands', flag: '🇳🇱'),
  RecipeOriginCountry(
      code: 'BE', nameRu: 'Бельгия', nameEn: 'Belgium', flag: '🇧🇪'),
  RecipeOriginCountry(
      code: 'AT', nameRu: 'Австрия', nameEn: 'Austria', flag: '🇦🇹'),
  RecipeOriginCountry(
      code: 'CH', nameRu: 'Швейцария', nameEn: 'Switzerland', flag: '🇨🇭'),
  RecipeOriginCountry(
      code: 'PT', nameRu: 'Португалия', nameEn: 'Portugal', flag: '🇵🇹'),
  RecipeOriginCountry(
      code: 'IE', nameRu: 'Ирландия', nameEn: 'Ireland', flag: '🇮🇪'),
  RecipeOriginCountry(
      code: 'CY', nameRu: 'Кипр', nameEn: 'Cyprus', flag: '🇨🇾'),
  RecipeOriginCountry(code: 'AE', nameRu: 'ОАЭ', nameEn: 'UAE', flag: '🇦🇪'),
  RecipeOriginCountry(
      code: 'SA',
      nameRu: 'Саудовская Аравия',
      nameEn: 'Saudi Arabia',
      flag: '🇸🇦'),
  RecipeOriginCountry(code: 'IR', nameRu: 'Иран', nameEn: 'Iran', flag: '🇮🇷'),
  RecipeOriginCountry(
      code: 'PK', nameRu: 'Пакистан', nameEn: 'Pakistan', flag: '🇵🇰'),
  RecipeOriginCountry(
      code: 'ID', nameRu: 'Индонезия', nameEn: 'Indonesia', flag: '🇮🇩'),
  RecipeOriginCountry(
      code: 'MY', nameRu: 'Малайзия', nameEn: 'Malaysia', flag: '🇲🇾'),
  RecipeOriginCountry(
      code: 'SG', nameRu: 'Сингапур', nameEn: 'Singapore', flag: '🇸🇬'),
  RecipeOriginCountry(
      code: 'PH', nameRu: 'Филиппины', nameEn: 'Philippines', flag: '🇵🇭'),
  RecipeOriginCountry(
      code: 'MN', nameRu: 'Монголия', nameEn: 'Mongolia', flag: '🇲🇳'),
  RecipeOriginCountry(
      code: 'KG', nameRu: 'Кыргызстан', nameEn: 'Kyrgyzstan', flag: '🇰🇬'),
  RecipeOriginCountry(
      code: 'TJ', nameRu: 'Таджикистан', nameEn: 'Tajikistan', flag: '🇹🇯'),
  RecipeOriginCountry(
      code: 'TM', nameRu: 'Туркменистан', nameEn: 'Turkmenistan', flag: '🇹🇲'),
  RecipeOriginCountry(
      code: 'ZA', nameRu: 'ЮАР', nameEn: 'South Africa', flag: '🇿🇦'),
  RecipeOriginCountry(
      code: 'ET', nameRu: 'Эфиопия', nameEn: 'Ethiopia', flag: '🇪🇹'),
  RecipeOriginCountry(code: 'CU', nameRu: 'Куба', nameEn: 'Cuba', flag: '🇨🇺'),
  RecipeOriginCountry(code: 'PE', nameRu: 'Перу', nameEn: 'Peru', flag: '🇵🇪'),
  RecipeOriginCountry(
      code: 'CO', nameRu: 'Колумбия', nameEn: 'Colombia', flag: '🇨🇴'),
  RecipeOriginCountry(
      code: 'CL', nameRu: 'Чили', nameEn: 'Chile', flag: '🇨🇱'),
  RecipeOriginCountry(
      code: 'NZ',
      nameRu: 'Новая Зеландия',
      nameEn: 'New Zealand',
      flag: '🇳🇿'),
  RecipeOriginCountry(
      code: 'IS', nameRu: 'Исландия', nameEn: 'Iceland', flag: '🇮🇸'),
  RecipeOriginCountry(
      code: 'DK', nameRu: 'Дания', nameEn: 'Denmark', flag: '🇩🇰'),
  RecipeOriginCountry(
      code: 'HR', nameRu: 'Хорватия', nameEn: 'Croatia', flag: '🇭🇷'),
  RecipeOriginCountry(
      code: 'SI', nameRu: 'Словения', nameEn: 'Slovenia', flag: '🇸🇮'),
  RecipeOriginCountry(
      code: 'SK', nameRu: 'Словакия', nameEn: 'Slovakia', flag: '🇸🇰'),
  RecipeOriginCountry(
      code: 'BA',
      nameRu: 'Босния и Герцеговина',
      nameEn: 'Bosnia',
      flag: '🇧🇦'),
  RecipeOriginCountry(
      code: 'MK',
      nameRu: 'Северная Македония',
      nameEn: 'North Macedonia',
      flag: '🇲🇰'),
  RecipeOriginCountry(
      code: 'AL', nameRu: 'Албания', nameEn: 'Albania', flag: '🇦🇱'),
  RecipeOriginCountry(
      code: 'ME', nameRu: 'Черногория', nameEn: 'Montenegro', flag: '🇲🇪'),
];

RecipeOriginCountry? findRecipeOriginCountry(String? code) {
  if (code == null || code.trim().isEmpty) return null;
  final upper = code.trim().toUpperCase();
  for (final c in kRecipeOriginCountries) {
    if (c.code == upper) return c;
  }
  return null;
}

String? recipeOriginLabelFromBody(Map<String, dynamic>? body) {
  if (body == null) return null;
  final code = body['origin_country_code'];
  if (code is String && code.isNotEmpty) {
    final found = findRecipeOriginCountry(code);
    if (found != null) return found.displayLabel;
    final name = body['origin_country_name'];
    if (name is String && name.isNotEmpty) return name;
  }
  return null;
}
