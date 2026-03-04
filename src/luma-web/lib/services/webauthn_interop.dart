/// WebAuthn browser interop for passkey registration and login ceremonies.
///
/// Uses `package:web` (dart:js_interop-backed) to call
/// `navigator.credentials.create()` and `navigator.credentials.get()`.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Calls `navigator.credentials.create()` with the server-provided
/// [creationOptions] JSON. Returns a JSON-serializable map ready to POST
/// back to `/api/auth/passkeys/register/finish`.
Future<Map<String, dynamic>> createCredential(
    Map<String, dynamic> creationOptions) async {
  final publicKey = creationOptions['publicKey'] as Map<String, dynamic>;

  // Build the JS options object, base64url-decoding binary fields.
  final challenge = _b64urlDecode(publicKey['challenge'] as String);
  final userId = _b64urlDecode(
      (publicKey['user'] as Map<String, dynamic>)['id'] as String);

  final excludeList = <web.PublicKeyCredentialDescriptor>[];
  final excludeCreds = publicKey['excludeCredentials'] as List<dynamic>?;
  if (excludeCreds != null) {
    for (final c in excludeCreds) {
      final m = c as Map<String, dynamic>;
      excludeList.add(web.PublicKeyCredentialDescriptor(
        type: 'public-key',
        id: _toJSArrayBuffer(_b64urlDecode(m['id'] as String)),
      ));
    }
  }

  // Build the Relying Party descriptor.
  final rpJson = publicKey['rp'] as Map<String, dynamic>;
  final rp = web.PublicKeyCredentialRpEntity(
    name: rpJson['name'] as String,
    id: rpJson['id'] as String? ?? '',
  );

  // Build the User descriptor.
  final userJson = publicKey['user'] as Map<String, dynamic>;
  final user = web.PublicKeyCredentialUserEntity(
    name: userJson['name'] as String,
    displayName: userJson['displayName'] as String,
    id: _toJSArrayBuffer(userId),
  );

  // Build pub key credential params.
  final pubKeyParams = <web.PublicKeyCredentialParameters>[];
  final paramsJson = publicKey['pubKeyCredParams'] as List<dynamic>;
  for (final p in paramsJson) {
    final m = p as Map<String, dynamic>;
    pubKeyParams.add(web.PublicKeyCredentialParameters(
      type: 'public-key',
      alg: m['alg'] as int,
    ));
  }

  // Build authenticator selection.
  final authSelJson =
      publicKey['authenticatorSelection'] as Map<String, dynamic>?;
  final authenticatorSelection = web.AuthenticatorSelectionCriteria(
    authenticatorAttachment:
        authSelJson?['authenticatorAttachment'] as String? ?? '',
    residentKey: authSelJson?['residentKey'] as String? ?? '',
    requireResidentKey: authSelJson?['requireResidentKey'] as bool? ?? false,
    userVerification: authSelJson?['userVerification'] as String? ?? '',
  );

  final options = web.CredentialCreationOptions(
    publicKey: web.PublicKeyCredentialCreationOptions(
      rp: rp,
      user: user,
      challenge: _toJSArrayBuffer(challenge),
      pubKeyCredParams: pubKeyParams.toJS,
      timeout: (publicKey['timeout'] as num?)?.toInt() ?? 60000,
      excludeCredentials: excludeList.toJS,
      authenticatorSelection: authenticatorSelection,
      attestation: publicKey['attestation'] as String? ?? 'none',
    ),
  );

  final credential = await web.window.navigator.credentials
      .create(options)
      .toDart as web.PublicKeyCredential;

  final response = credential.response as web.AuthenticatorAttestationResponse;

  return {
    'id': credential.id,
    'rawId': _b64urlEncode(_fromJSArrayBuffer(credential.rawId)),
    'type': credential.type,
    'response': {
      'attestationObject':
          _b64urlEncode(_fromJSArrayBuffer(response.attestationObject)),
      'clientDataJSON':
          _b64urlEncode(_fromJSArrayBuffer(response.clientDataJSON)),
    },
  };
}

/// Calls `navigator.credentials.get()` with the server-provided
/// [assertionOptions] JSON. Returns a JSON-serializable map ready to POST
/// back to `/api/auth/passkeys/login/finish`.
Future<Map<String, dynamic>> getCredential(
    Map<String, dynamic> assertionOptions) async {
  final publicKey = assertionOptions['publicKey'] as Map<String, dynamic>;

  final challenge = _b64urlDecode(publicKey['challenge'] as String);

  final allowList = <web.PublicKeyCredentialDescriptor>[];
  final allowCreds = publicKey['allowCredentials'] as List<dynamic>?;
  if (allowCreds != null) {
    for (final c in allowCreds) {
      final m = c as Map<String, dynamic>;
      allowList.add(web.PublicKeyCredentialDescriptor(
        type: 'public-key',
        id: _toJSArrayBuffer(_b64urlDecode(m['id'] as String)),
      ));
    }
  }

  final options = web.CredentialRequestOptions(
    publicKey: web.PublicKeyCredentialRequestOptions(
      challenge: _toJSArrayBuffer(challenge),
      rpId: publicKey['rpId'] as String? ?? '',
      timeout: (publicKey['timeout'] as num?)?.toInt() ?? 60000,
      allowCredentials: allowList.toJS,
      userVerification: publicKey['userVerification'] as String? ?? '',
    ),
  );

  final credential = await web.window.navigator.credentials.get(options).toDart
      as web.PublicKeyCredential;

  final response = credential.response as web.AuthenticatorAssertionResponse;

  return {
    'id': credential.id,
    'rawId': _b64urlEncode(_fromJSArrayBuffer(credential.rawId)),
    'type': credential.type,
    'response': {
      'authenticatorData':
          _b64urlEncode(_fromJSArrayBuffer(response.authenticatorData)),
      'clientDataJSON':
          _b64urlEncode(_fromJSArrayBuffer(response.clientDataJSON)),
      'signature': _b64urlEncode(_fromJSArrayBuffer(response.signature)),
      'userHandle': response.userHandle != null
          ? _b64urlEncode(_fromJSArrayBuffer(response.userHandle!))
          : null,
    },
  };
}

// ── Base64url helpers ──────────────────────────────────────────────────────

Uint8List _b64urlDecode(String input) {
  // Add padding if needed.
  String padded = input.replaceAll('-', '+').replaceAll('_', '/');
  switch (padded.length % 4) {
    case 2:
      padded += '==';
      break;
    case 3:
      padded += '=';
      break;
  }
  return base64.decode(padded);
}

String _b64urlEncode(Uint8List bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

JSArrayBuffer _toJSArrayBuffer(Uint8List bytes) {
  return bytes.buffer.toJS;
}

Uint8List _fromJSArrayBuffer(JSArrayBuffer buffer) {
  return buffer.toDart.asUint8List();
}
