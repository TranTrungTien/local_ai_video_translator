class DiagnosticsExporter {
  const DiagnosticsExporter();

  /// Exports local diagnostics report with sensitive values (cookies, auth headers, tokens) strictly redacted.
  String exportRedactedReport({
    required String sourceUri,
    required Map<String, String> headers,
    required List<String> logEvents,
  }) {
    final sanitizedUri = _redactUriTokens(sourceUri);
    final sanitizedHeaders = _redactHeaders(headers);
    final sanitizedLogs = logEvents.map(_redactLogMessage).toList();

    return '''
=== LOCAL AI VIDEO TRANSLATOR DIAGNOSTICS EXPORT ===
Source URI: $sanitizedUri
Headers: $sanitizedHeaders
-----------------------------------------------------
Logs:
${sanitizedLogs.join('\n')}
=====================================================
''';
  }

  String _redactUriTokens(String uriStr) {
    try {
      final uri = Uri.parse(uriStr);
      final queryParams = Map<String, String>.from(uri.queryParameters);
      for (final key in queryParams.keys) {
        if (key.toLowerCase().contains('token') ||
            key.toLowerCase().contains('auth') ||
            key.toLowerCase().contains('sig') ||
            key.toLowerCase().contains('key')) {
          queryParams[key] = '[REDACTED]';
        }
      }
      return uri
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null)
          .toString();
    } catch (_) {
      return '[REDACTED_URI]';
    }
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    final redacted = <String, String>{};
    for (final entry in headers.entries) {
      final keyLower = entry.key.toLowerCase();
      if (keyLower.contains('authorization') ||
          keyLower.contains('cookie') ||
          keyLower.contains('token') ||
          keyLower.contains('api-key')) {
        redacted[entry.key] = '[REDACTED]';
      } else {
        redacted[entry.key] = entry.value;
      }
    }
    return redacted;
  }

  String _redactLogMessage(String message) {
    // Redact potential tokens or passwords in log lines
    var sanitized = message.replaceAll(
      RegExp(r'token=[^&\s]+', caseSensitive: false),
      'token=[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'authorization:[^\s]+', caseSensitive: false),
      'authorization:[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'key=[^&\s]+', caseSensitive: false),
      'key=[REDACTED]',
    );
    return sanitized;
  }
}
