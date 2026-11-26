/// App-wide string constants, supported currencies, travel styles, and interests.
class AppStrings {
  AppStrings._();

  static const String appName = 'AI Travel Planner';
  static const String appTagline =
      'Plan smart, verified day-by-day trips powered by AI.';

  static const String exploreAsGuest = 'Explore as Guest';
  static const String signIn = 'Sign In';

  static const int maxTripDays = 14;
  static const double maxBudget = 1000000.0;

  static const List<String> supportedCurrencies = [
    'PKR',
    'USD',
    'AED',
    'GBP',
    'EUR',
  ];

  static const Map<String, String> currencySymbols = {
    'USD': r'$',
    'EUR': '€',
    'PKR': 'Rs ',
    'AED': 'AED ',
    'GBP': '£',
  };

  static const List<String> travelStyles = [
    'Budget',
    'Moderate',
    'Luxury',
  ];

  static const List<String> defaultInterests = [
    'Nature',
    'Photography',
    'Local Food',
    'Hiking',
    'Historical',
    'Culture',
    'Adventure',
    'Shopping',
    'Relaxation',
  ];

  static const List<String> expenseCategories = [
    'Food',
    'Transport',
    'Accommodation',
    'Activities',
    'Shopping',
    'Other',
  ];
}
