import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

/// A universal image widget for PawWatch that reliably renders:
/// 1. Base64 data URIs ('data:image/...;base64,...' or 'base64,...')
/// 2. Remote HTTP / HTTPS URLs ('https://...')
/// 3. Local filesystem paths ('/data/user/0/...' or 'C:\...')
/// 4. Raw Base64 string fallback
class PawImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const PawImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  Widget _defaultFallback() {
    return errorWidget ??
        placeholder ??
        Container(
          width: width,
          height: height,
          color: const Color(0xFF9C27B0).withValues(alpha: 0.12),
          child: Center(
            child: Icon(
              Icons.pets,
              size: (width != null && width! < 60) ? 20 : 36,
              color: const Color(0xFF9C27B0).withValues(alpha: 0.4),
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    Widget content = _buildImage(context);
    if (borderRadius != null) {
      content = ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }
    return content;
  }

  Widget _buildImage(BuildContext context) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return _defaultFallback();
    }

    // 1. Base64 data URI format (e.g. data:image/jpeg;base64,/9j/...)
    if (trimmed.startsWith('data:image') || trimmed.startsWith('base64,')) {
      try {
        final commaIdx = trimmed.indexOf(',');
        final b64 = commaIdx != -1 ? trimmed.substring(commaIdx + 1) : trimmed;
        final cleanB64 = b64.replaceAll('\n', '').replaceAll('\r', '').trim();
        final bytes = base64Decode(cleanB64);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _defaultFallback(),
        );
      } catch (e) {
        debugPrint('PawImage Base64 decode error: $e');
        return _defaultFallback();
      }
    }

    // 2. HTTP / HTTPS network image
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (ctx, err, stack) {
          // If network failed, check if the string happens to be a valid local file
          try {
            final file = File(trimmed);
            if (file.existsSync()) {
              return Image.file(file, width: width, height: height, fit: fit);
            }
          } catch (_) {}
          return _defaultFallback();
        },
      );
    }

    // 3. Local filesystem file
    try {
      final file = File(trimmed);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _defaultFallback(),
        );
      }
    } catch (_) {}

    // 4. Raw base64 string fallback (no data URI prefix, but valid base64 payload)
    if (trimmed.length > 100 &&
        !trimmed.startsWith('/') &&
        !trimmed.contains('\\') &&
        !trimmed.contains(' ')) {
      try {
        final clean = trimmed.replaceAll('\n', '').replaceAll('\r', '').trim();
        final bytes = base64Decode(clean);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _defaultFallback(),
        );
      } catch (_) {}
    }

    return _defaultFallback();
  }
}
