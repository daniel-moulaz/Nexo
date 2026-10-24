/// Project coordinates injected at build time, never committed:
/// `flutter build ... --dart-define-from-file=tool/nexo_sync.local.json`
/// The publishable key identifies the app, not a person; row level security
/// on the server protects each dataset. Admin keys never belong here.
class SyncConfig {
  const SyncConfig(this.projectUrl, this.publishableKey);
  final Uri projectUrl;
  final String publishableKey;

  static const _url = String.fromEnvironment('NEXO_SUPABASE_URL');
  static const _key = String.fromEnvironment('NEXO_SUPABASE_KEY');

  /// Null when this build has no sync project configured.
  static SyncConfig? get current {
    if (_url.isEmpty || _key.isEmpty) return null;
    final uri = Uri.tryParse(_url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    if (!_key.startsWith('sb_publishable_')) return null;
    return SyncConfig(uri, _key);
  }
}
