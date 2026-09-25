import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../errors/app_exception.dart';

/// Envuelve una llamada RPC de Supabase traduciendo errores de red y de
/// autenticación a [AppException] tipadas.
Future<Map<String, dynamic>> callRpc(
  Future<Map<String, dynamic>> Function() action,
) async {
  try {
    return await action();
  } on TimeoutException {
    throw const NetworkException();
  } on SocketException {
    throw const NetworkException();
  } on http.ClientException {
    throw const NetworkException();
  } on supabase.PostgrestException {
    throw const QueryException('No pudimos completar la acción. Intenta de nuevo.');
  } on supabase.AuthException {
    throw const QueryException(
      'No pudimos completar la acción. Cierra y abre la app de nuevo.',
    );
  }
}
