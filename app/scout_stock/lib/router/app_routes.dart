class AppRoutes {
  AppRoutes._();

  // System
  static const String root = '/';
  static const String loading = '/loading';
  static const String error = '/error';

  // Scout / common
  static const String scan = '/scan';
  static const String cart = '/cart';
  static const String me = '/me';
  static const String manualEntry = '/manual';

  static String bucket(String barcode) =>
      '/bucket/${Uri.encodeComponent(barcode)}';

  // Admin shell (tabs)
  static const String adminBase = '/a';
  static const String adminScan = '/a/scan';
  static const String adminCart = '/a/cart';
  static const String adminMe = '/a/me';
  static const String adminManage = '/a/manage';
  static const String adminActivity = '/a/activity';
  static const String adminUsers = '/a/users';
}