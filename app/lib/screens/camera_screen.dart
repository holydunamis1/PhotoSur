import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../generated/l10n/app_localizations.dart';
import '../platform/permission_service.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/loading_overlay.dart';
import '../widgets/toast_notification.dart';
import 'unsupported_device_screen.dart';

/// Full-screen preview (cover-fit, not stretched), corner framing guide,
/// shutter, flash toggle and gallery shortcut.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _flashOn = false;
  bool _initializing = true;
  // Stores which localized message to show, resolved at build time via
  // AppLocalizations rather than storing the resolved String directly —
  // this state is set from initState/async callbacks that may run before
  // a BuildContext with a resolved locale is guaranteed usable.
  _CameraErrorType? _errorType;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final result = await PermissionService.instance.requestCameraPermission();
    switch (result) {
      case PermissionResult.granted:
        await _initCamera();
        break;
      case PermissionResult.denied:
        setState(() {
          _initializing = false;
          _errorType = _CameraErrorType.permissionDenied;
        });
        break;
      case PermissionResult.permanentlyDenied:
        setState(() {
          _initializing = false;
          _errorType = _CameraErrorType.permissionPermanentlyDenied;
        });
        break;
      case PermissionResult.restricted:
        setState(() {
          _initializing = false;
          _errorType = _CameraErrorType.permissionRestricted;
        });
        break;
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          context.pushReplacement(
            '/unsupported-device',
            extra: UnsupportedReason.noCamera,
          );
        }
        return;
      }
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorType = _CameraErrorType.startFailed;
      });
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final newMode = _flashOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(newMode);
      setState(() => _flashOn = !_flashOn);
    } catch (e) {
      // Flash unsupported on this device/camera — silently no-op rather
      // than crash, matches the graceful-degradation architecture rule.
    }
  }

  Future<void> _capture(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      final file = await controller.takePicture();
      if (!context.mounted) return;
      context.push('/crop', extra: file.path);
    } catch (e) {
      if (context.mounted) {
        ToastNotification.show(context, message: l10n.cameraCaptureFailed, type: ToastType.error);
      }
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !context.mounted) return;
      context.push('/crop', extra: picked.path);
    } catch (e) {
      // ignore: avoid_print
      print('Gallery pick failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String? _errorMessage(AppLocalizations l10n) {
    return switch (_errorType) {
      null => null,
      _CameraErrorType.permissionDenied => l10n.cameraPermissionDenied,
      _CameraErrorType.permissionPermanentlyDenied =>
        l10n.cameraPermissionPermanentlyDenied,
      _CameraErrorType.permissionRestricted => l10n.cameraPermissionRestricted,
      _CameraErrorType.startFailed => l10n.cameraStartFailed,
    };
  }

  /// Fills the screen without stretching: the preview is scaled to cover
  /// and the overflow is clipped.
  Widget _preview(BuildContext context, CameraController controller) {
    final sensorRatio = controller.value.aspectRatio; // long side / short side
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final ratio = landscape ? sensorRatio : 1 / sensorRatio; // width / height
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 1000,
          height: 1000 / ratio,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final errorMessage = _errorMessage(l10n);
    final ready = _controller != null && _controller!.value.isInitialized;

    return AppScaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              _preview(context, _controller!)
            else if (errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(
                    errorMessage,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            // Corner guide: frames the subject for background removal.
            if (ready)
              const IgnorePointer(
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.8,
                    heightFactor: 0.6,
                    child: CustomPaint(painter: _CornerGuidePainter()),
                  ),
                ),
              ),
            // Top bar: back + title over a soft scrim.
            PositionedDirectional(
              top: 0,
              start: 0,
              end: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 16, 16),
                  child: Row(
                    children: [
                      _RoundButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        mirror: true,
                        tooltip: MaterialLocalizations.of(context)
                            .backButtonTooltip,
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.cameraTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB3000000)],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 28),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RoundButton(
                          icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          tooltip: l10n.cameraFlashTooltip,
                          highlighted: _flashOn,
                          onPressed: _toggleFlash,
                        ),
                        _ShutterButton(
                          semanticLabel: l10n.cameraTitle,
                          onPressed: () => _capture(context),
                        ),
                        _RoundButton(
                          icon: Icons.photo_library_outlined,
                          tooltip: l10n.cameraGalleryTooltip,
                          onPressed: () => _pickFromGallery(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_errorType == _CameraErrorType.permissionPermanentlyDenied)
              Positioned(
                bottom: 32,
                left: 24,
                right: 24,
                child: FilledButton(
                  onPressed: () => PermissionService.instance.openSettings(),
                  child: Text(l10n.cameraOpenSettings),
                ),
              ),
            LoadingOverlay(visible: _initializing),
          ],
        ),
      ),
    );
  }
}

/// 56 dp translucent circular control used over the live preview.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.mirror = false,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool mirror;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final flip = mirror && Directionality.of(context) == TextDirection.rtl;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Material(
          color: highlighted
              ? Colors.white
              : Colors.black.withValues(alpha: 0.35),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              onPressed();
            },
            child: Transform.flip(
              flipX: flip,
              child: Icon(
                icon,
                size: 24,
                color: highlighted ? Colors.black : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 80 dp shutter: white ring with an inner disc that shrinks while pressed.
class _ShutterButton extends StatefulWidget {
  const _ShutterButton({required this.onPressed, required this.semanticLabel});

  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  State<_ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<_ShutterButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: () {
          HapticFeedback.mediumImpact();
          widget.onPressed();
        },
        child: Container(
          width: 80,
          height: 80,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: AnimatedScale(
            scale: _down ? 0.86 : 1,
            duration: const Duration(milliseconds: 90),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Four white corner brackets marking the framing area.
class _CornerGuidePainter extends CustomPainter {
  const _CornerGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    const len = 30.0;
    const r = 14.0;
    final w = size.width;
    final h = size.height;
    final path = Path()
      // top-left
      ..moveTo(0, len)
      ..lineTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(len, 0)
      // top-right
      ..moveTo(w - len, 0)
      ..lineTo(w - r, 0)
      ..quadraticBezierTo(w, 0, w, r)
      ..lineTo(w, len)
      // bottom-right
      ..moveTo(w, h - len)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(w - len, h)
      // bottom-left
      ..moveTo(len, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..lineTo(0, h - len);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum _CameraErrorType {
  permissionDenied,
  permissionPermanentlyDenied,
  permissionRestricted,
  startFailed,
}
