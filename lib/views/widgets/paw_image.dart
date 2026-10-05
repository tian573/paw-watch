import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';


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


    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (ctx, err, stack) {

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


