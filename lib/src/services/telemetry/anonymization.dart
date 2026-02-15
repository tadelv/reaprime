import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Privacy utilities for anonymizing PII in telemetry
///
/// Uses salted SHA-256 hashing to produce consistent identifiers without
/// storing reversible information. Follows the pattern from ProfileHash.
class Anonymization {
  /// Fixed app-specific salt for all anonymization operations
  static const String _salt = 'reaprime-telemetry-v1';

  /// Anonymize a Bluetooth MAC address
  ///
  /// Normalizes the MAC address (uppercase, removes separators), then
  /// applies salted SHA-256 hashing. Returns a 16-character hex prefix
  /// suitable for correlation without reversibility.
  ///
  /// Example: "AA:BB:CC:DD:EE:FF" -> "mac_1a2b3c4d5e6f7a8b"
  static String anonymizeMac(String macAddress) {
    // Normalize: uppercase, remove colons and dashes
    final normalized = macAddress
        .toUpperCase()
        .replaceAll(':', '')
        .replaceAll('-', '');

    // Concatenate salt, type, and value
    final input = '$_salt:mac:$normalized';

    // SHA-256 hash
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);

    // Return first 16 hex chars (64 bits)
    return 'mac_${hash.toString().substring(0, 16)}';
  }

  /// Anonymize an IP address (IPv4 or IPv6)
  ///
  /// Applies salted SHA-256 hashing to the IP address.
  /// Returns a 16-character hex prefix for correlation.
  ///
  /// Example: "192.168.1.1" -> "ip_9f8e7d6c5b4a3b2c"
  static String anonymizeIp(String ipAddress) {
    // Concatenate salt, type, and value
    final input = '$_salt:ip:$ipAddress';

    // SHA-256 hash
    final bytes = utf8.encode(input);
    final hash = sha256.convert(bytes);

    // Return first 16 hex chars (64 bits)
    return 'ip_${hash.toString().substring(0, 16)}';
  }

  /// General-purpose anonymization with automatic detection
  ///
  /// Detects MAC addresses, IPv4, and IPv6 patterns and routes to
  /// the appropriate anonymization method. Returns input unchanged
  /// if no PII pattern is detected.
  static String anonymize(String input) {
    // MAC address pattern: XX:XX:XX:XX:XX:XX or XX-XX-XX-XX-XX-XX
    final macPattern = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$');
    if (macPattern.hasMatch(input)) {
      return anonymizeMac(input);
    }

    // IPv4 pattern: N.N.N.N
    final ipv4Pattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    if (ipv4Pattern.hasMatch(input)) {
      return anonymizeIp(input);
    }

    // IPv6 pattern: contains multiple colons and hex chars
    final ipv6Pattern = RegExp(r'^[0-9A-Fa-f:]+$');
    if (input.contains(':') && ipv6Pattern.hasMatch(input)) {
      return anonymizeIp(input);
    }

    // No PII detected, return unchanged
    return input;
  }

  /// Scrub PII from arbitrary text
  ///
  /// Finds all MAC addresses and IP addresses in the text and replaces
  /// them with anonymized versions. Useful for cleaning log messages
  /// before uploading to telemetry services.
  static String scrubString(String text) {
    var scrubbed = text;

    // Find and replace all MAC addresses
    final macPattern = RegExp(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}');
    scrubbed = scrubbed.replaceAllMapped(macPattern, (match) {
      return anonymizeMac(match.group(0)!);
    });

    // Find and replace all IPv4 addresses
    final ipv4Pattern = RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b');
    scrubbed = scrubbed.replaceAllMapped(ipv4Pattern, (match) {
      return anonymizeIp(match.group(0)!);
    });

    // Note: IPv6 scrubbing is more complex due to varied formats
    // For Phase 1, focusing on MAC and IPv4 as primary PII in device logs

    return scrubbed;
  }
}
