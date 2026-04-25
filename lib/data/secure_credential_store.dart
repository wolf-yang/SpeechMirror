import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureCredentialStore {
  static const _kBaseUrl = 'sm_base_url';
  static const _kModel = 'sm_model';
  static const _kApiKey = 'sm_api_key';

  final FlutterSecureStorage _storage;

  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<String?> readBaseUrl() => _storage.read(key: _kBaseUrl);
  Future<String?> readModel() => _storage.read(key: _kModel);
  Future<String?> readApiKey() => _storage.read(key: _kApiKey);

  Future<void> writeBaseUrl(String? v) async {
    if (v == null || v.isEmpty) {
      await _storage.delete(key: _kBaseUrl);
    } else {
      await _storage.write(key: _kBaseUrl, value: v.trim());
    }
  }

  Future<void> writeModel(String? v) async {
    if (v == null || v.isEmpty) {
      await _storage.delete(key: _kModel);
    } else {
      await _storage.write(key: _kModel, value: v.trim());
    }
  }

  Future<void> writeApiKey(String? v) async {
    if (v == null || v.isEmpty) {
      await _storage.delete(key: _kApiKey);
    } else {
      await _storage.write(key: _kApiKey, value: v.trim());
    }
  }

  Future<void> wipeAll() async {
    await _storage.deleteAll();
  }
}
