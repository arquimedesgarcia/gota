import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../errors/app_exception.dart';

/// Envuelve una llamada RPC de Supabase traduciendo errores de red y de
/// autenticación a [AppException] tipadas.
///
/// [networkMessage] y [authMessage] permiten personalizar el mensaje de error
/// visible; si se omiten se usan los mensajes por defecto de [NetworkException]
/// y [QueryException].
Future<Map<String, dynamic>> callRpc(
  Future<Map<String, dynamic>> Function() action, {
  String? networkMessage,
  String? authMessage,
}) async {
  try {
    return await action();
  } on TimeoutException {
    throw networkMessage != null
        ? NetworkException(networkMessage)
        : const NetworkException();
  } on SocketException {
    throw networkMessage != null
        ? NetworkException(networkMessage)
        : const NetworkException();
  } on http.ClientException {
    throw networkMessage != null
        ? NetworkException(networkMessage)
        : const NetworkException();
  } on supabase.PostgrestException {
    throw authMessage != null
        ? QueryException(authMessage)
        : const QueryException('No pudimos completar la acción. Intenta de nuevo.');
  } on supabase.AuthException {
    throw const QueryException(
      'No pudimos completar la acción. Cierra y abre la app de nuevo.',
    );
  }
}
