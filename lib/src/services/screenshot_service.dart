import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:logging/logging.dart';

/// Service for capturing screenshots of the current app screen.
///
/// Uses Flutter's RepaintBoundary approach - no additional dependencies needed.
class ScreenshotService {
  static final Logger _log = Logger('ScreenshotService');

  /// Global key that should be attached to a RepaintBoundary wrapping
  /// the content you want to capture.
  static final GlobalKey screenshotKey = GlobalKey();

  /// Capture the current screen content as PNG bytes.
  ///
  /// Returns null if capture fails or no RepaintBoundary is found.
  static Future<Uint8List?> captureScreen(BuildContext context) async {
    try {
      final boundary = screenshotKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        _log.warning('No RepaintBoundary found for screenshot capture');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData == null) {
        _log.warning('Failed to convert screenshot to bytes');
        return null;
      }

      _log.info('Screenshot captured: ${byteData.lengthInBytes} bytes');
      return byteData.buffer.asUint8List();
    } catch (e, st) {
      _log.severe('Failed to capture screenshot', e, st);
      return null;
    }
  }
}
