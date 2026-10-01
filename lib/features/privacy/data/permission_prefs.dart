import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionPrefs {
  PermissionPrefs._(this._prefs);
  final SharedPreferences _prefs;

  static Future<PermissionPrefs> load() async =>
      PermissionPrefs._(await SharedPreferences.getInstance());

  static const _kTerms = 'privacy_terms_shown';
  static const _kLocation = 'location_rationale_shown';
  static const _kNotif = 'notif_rationale_shown';

  bool get termsShown => _prefs.getBool(_kTerms) ?? false;
  bool get locationRationaleShown => _prefs.getBool(_kLocation) ?? false;
  bool get notifRationaleShown => _prefs.getBool(_kNotif) ?? false;

  Future<void> setTermsShown() => _prefs.setBool(_kTerms, true);
  Future<void> setLocationRationaleShown() =>
      _prefs.setBool(_kLocation, true);
  Future<void> setNotifRationaleShown() => _prefs.setBool(_kNotif, true);
}

final permissionPrefsProvider = FutureProvider<PermissionPrefs>(
  (ref) => PermissionPrefs.load(),
);

/// True cuando el usuario ya vio el diálogo de razonamiento de notificaciones.
/// pushBootstrapProvider lo mira como compuerta antes de pedir el permiso del SO.
final notifRationaleShownProvider = FutureProvider<bool>((ref) async {
  final prefs = await ref.watch(permissionPrefsProvider.future);
  return prefs.notifRationaleShown;
});
