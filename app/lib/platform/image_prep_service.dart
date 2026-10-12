import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/services/mask_pipeline.dart';
import '../core/utils/constants.dart';

class ImagePrepException implements Exception {
  const ImagePrepException(this.message);
  final String message;

  @override
  String toString() => 'ImagePrepException: $message';
}

/// Result of [prepareImage]: the file the editor should work on (possibly a
/// normalised copy), its pixel size, and the model input tensor.
class PreparedImage {
  const PreparedImage({
    required this.path,
    required this.width,
    required this.height,
    required this.modelInput,
    required this.guideGray,
  });

  final String path;
  final int width;
  final int height;
  final Float32List modelInput;

  /// 8-bit luminance of the working image (width x height), used to snap the
  /// mask's edges to the photo's real edges.
  final Uint8List guideGray;
}

/// Decodes [sourcePath], fixes EXIF rotation, caps the longest edge at
/// [kMaxWorkingEdgePx], and builds the model input — all in a background
/// isolate. A normalised copy is written into [workDir] only when the
/// original can't be used as-is (rotated by EXIF, too large, or has an
/// alpha channel); otherwise the original path is returned untouched.
Future<PreparedImage> prepareImage(String sourcePath, String workDir) {
  return Isolate.run(() => _prepare(sourcePath, workDir));
}

Future<PreparedImage> _prepare(String sourcePath, String workDir) async {
  final bytes = await File(sourcePath).readAsBytes();
  var image = img.decodeImage(bytes);
  if (image == null) {
    throw const ImagePrepException('Could not decode image.');
  }

  var needsRewrite = false;

  // Normalise exotic formats so the RGB read below is always 8-bit RGB(A).
  if (image.format != img.Format.uint8) {
    image = image.convert(format: img.Format.uint8);
  }
  if (image.numChannels < 3) {
    image = image.convert(numChannels: 3);
  }

  final orientation = image.exif.imageIfd.orientation ?? 1;
  if (orientation != 1) {
    image = img.bakeOrientation(image);
    needsRewrite = true;
  }

  final longest = image.width > image.height ? image.width : image.height;
  if (longest > kMaxWorkingEdgePx) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: kMaxWorkingEdgePx,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: kMaxWorkingEdgePx,
            interpolation: img.Interpolation.average,
          );
    needsRewrite = true;
  }

  final hasAlpha = image.numChannels == 4;
  if (hasAlpha) needsRewrite = true;

  var workingPath = sourcePath;
  if (needsRewrite) {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final useJpg = !hasAlpha;
    workingPath = '$workDir/working_$stamp.${useJpg ? 'jpg' : 'png'}';
    final encoded = useJpg
        ? img.encodeJpg(image, quality: 95)
        : img.encodePng(image);
    await File(workingPath).writeAsBytes(encoded);
  }

  // Model input: RGB only. Transparent pixels are flattened onto white so
  // PNGs with alpha don't feed black holes to the model.
  final rgb = Uint8List(image.width * image.height * 3);
  final gray = Uint8List(image.width * image.height);
  var o = 0;
  var g = 0;
  for (final p in image) {
    final a = hasAlpha ? p.a / 255.0 : 1.0;
    final r = (p.r * a + 255 * (1 - a)).round();
    final gr = (p.g * a + 255 * (1 - a)).round();
    final b = (p.b * a + 255 * (1 - a)).round();
    rgb[o++] = r;
    rgb[o++] = gr;
    rgb[o++] = b;
    gray[g++] = (0.299 * r + 0.587 * gr + 0.114 * b).round().clamp(0, 255);
  }

  return PreparedImage(
    path: workingPath,
    width: image.width,
    height: image.height,
    modelInput: preprocessRgb(rgb, image.width, image.height),
    guideGray: gray,
  );
}
