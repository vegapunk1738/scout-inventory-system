class EnvConfig {
  const EnvConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:8787',
  );
}