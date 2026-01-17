import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';

class CameraView extends StatefulWidget {
  const CameraView({super.key});

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  late List<CameraDescription> _cameras;
  CameraController? cameraController;

  late FaceDetector faceDetector;
  List<Face> detectedFaces = [];
  bool isProcessing = false;
  bool isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    initializeFaceDetector();
    cameraInitialize();
  }

  void initializeFaceDetector() {
    final options = FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    );
    faceDetector = FaceDetector(options: options);
  }

  void cameraInitialize() async {
    try {
      _cameras = await availableCameras();

      // Use front camera with MEDIUM resolution
      cameraController = CameraController(
        _cameras[1],
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21, // Ensure NV21 format
      );

      await cameraController!.initialize();

      if (mounted) {
        setState(() {
          isCameraInitialized = true;
        });

        // Start image stream
        cameraController!.startImageStream((CameraImage image) {
          if (!isProcessing) {
            isProcessing = true;
            detectFacesFromImage(image);
          }
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> detectFacesFromImage(CameraImage cameraImage) async {
    try {
      final inputImage = convertCameraImage(cameraImage);

      if (inputImage == null) {
        isProcessing = false;
        return;
      }

      final faces = await faceDetector.processImage(inputImage);

      if (mounted) {
        setState(() {
          detectedFaces = faces;
        });
      }
    } catch (e) {
      print('Error detecting faces: $e');
    } finally {
      isProcessing = false;
    }
  }

  InputImage? convertCameraImage(CameraImage cameraImage) {
    try {
      final camera = _cameras[1];
      final rotation = rotationIntToImageRotation(camera.sensorOrientation);

      // Create WriteBuffer for all planes
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in cameraImage.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        cameraImage.width.toDouble(),
        cameraImage.height.toDouble(),
      );

      final InputImageMetadata metadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: cameraImage.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: metadata,
      );
    } catch (e) {
      print('Error converting image: $e');
      return null;
    }
  }

  InputImageRotation rotationIntToImageRotation(int rotation) {
    switch (rotation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  @override
  void dispose() {
    cameraController?.stopImageStream();
    cameraController?.dispose();
    faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Face Detection',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
      ),
      body: !isCameraInitialized || cameraController == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(cameraController!),
          CustomPaint(
            size: Size.infinite,
            painter: FacePainter(
              faces: detectedFaces,
              imageSize: Size(
                cameraController!.value.previewSize!.height,
                cameraController!.value.previewSize!.width,
              ),
              cameraLensDirection: _cameras[1].lensDirection,
            ),
          ),
          Positioned(
            top: 100,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Faces Detected: ${detectedFaces.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (detectedFaces.isNotEmpty)
                    const Text(
                      'Analyzing...',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FacePainter extends CustomPainter {
  final List<Face> faces;
  final Size imageSize;
  final CameraLensDirection cameraLensDirection;

  FacePainter({
    required this.faces,
    required this.imageSize,
    required this.cameraLensDirection,
  });

  // Different colors for different faces
  final List<Color> faceColors = [
    Colors.green,
    Colors.blue,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.cyan,
    Colors.yellow,
    Colors.red,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint landmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red;

    for (int i = 0; i < faces.length; i++) {
      final face = faces[i];
      final color = faceColors[i % faceColors.length];

      // Draw rounded rectangle with different color for each face
      final Paint boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = color;

      final rect = _scaleRect(
        rect: face.boundingBox,
        imageSize: imageSize,
        widgetSize: size,
      );

      // Draw rounded rectangle
      final RRect roundedRect = RRect.fromRectAndRadius(
        rect,
        const Radius.circular(12),
      );
      canvas.drawRRect(roundedRect, boxPaint);

      // Draw face count badge
      _drawFaceBadge(canvas, rect, i + 1, color);

      // Draw smiling probability
      _drawSmilingProbability(canvas, face, rect, color);

      // Draw landmarks
      _drawLandmark(canvas, face, FaceLandmarkType.leftEye, landmarkPaint,
          imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.rightEye, landmarkPaint,
          imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.noseBase, landmarkPaint,
          imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.leftMouth, landmarkPaint,
          imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.rightMouth, landmarkPaint,
          imageSize, size);
    }
  }

  void _drawFaceBadge(Canvas canvas, Rect rect, int faceNumber, Color color) {
    // Badge background
    final Paint badgePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final double badgeSize = 30;
    final Offset badgePosition = Offset(rect.left - 5, rect.top - 5);

    // Draw circle badge
    canvas.drawCircle(
      badgePosition,
      badgeSize / 2,
      badgePaint,
    );

    // Draw badge border
    final Paint borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;

    canvas.drawCircle(
      badgePosition,
      badgeSize / 2,
      borderPaint,
    );

    // Draw face number
    final textSpan = TextSpan(
      text: '$faceNumber',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        badgePosition.dx - textPainter.width / 2,
        badgePosition.dy - textPainter.height / 2,
      ),
    );
  }

  void _drawSmilingProbability(
      Canvas canvas, Face face, Rect rect, Color color) {
    final double? smilingProb = face.smilingProbability;

    if (smilingProb != null) {
      // Background for smiling probability
      final Paint bgPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black87;

      final double boxWidth = 100;
      final double boxHeight = 30;
      final Offset boxPosition = Offset(
        rect.left,
        rect.bottom + 8,
      );

      final RRect bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(boxPosition.dx, boxPosition.dy, boxWidth, boxHeight),
        const Radius.circular(6),
      );

      canvas.drawRRect(bgRect, bgPaint);

      // Draw border
      final Paint borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color;

      canvas.drawRRect(bgRect, borderPaint);

      // Draw smiling text with emoji
      final String emoji = smilingProb > 0.7 ? 'Very Happy' : smilingProb > 0.3 ? 'Slight Smile' : 'Neutral';
      final textSpan = TextSpan(
        text: '$emoji ${(smilingProb * 100).toStringAsFixed(0)}%',
        style: TextStyle(
          color: smilingProb > 0.7 ? Colors.greenAccent : Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          boxPosition.dx + (boxWidth - textPainter.width) / 2,
          boxPosition.dy + (boxHeight - textPainter.height) / 2,
        ),
      );
    }
  }

  void _drawLandmark(
      Canvas canvas,
      Face face,
      FaceLandmarkType type,
      Paint paint,
      Size imageSize,
      Size widgetSize,
      ) {
    final landmark = face.landmarks[type];
    if (landmark != null) {
      final point = _scalePoint(
        point: landmark.position,
        imageSize: imageSize,
        widgetSize: widgetSize,
      );
      canvas.drawCircle(point, 5, paint);
    }
  }

  Rect _scaleRect({
    required Rect rect,
    required Size imageSize,
    required Size widgetSize,
  }) {
    // Calculate scale considering aspect ratio
    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    // Use the same scale for both dimensions to maintain aspect ratio
    final double scale = max(scaleX, scaleY);

    // Calculate offsets to center the image
    final double offsetX = (widgetSize.width - imageSize.width * scale) / 2;
    final double offsetY = (widgetSize.height - imageSize.height * scale) / 2;

    // Adjust width and height
    final double widthReduction = 0.15; // Reduce width by 15%
    final double heightIncrease = 0.10; // Increase height by 10%

    final double rectWidth = rect.width;
    final double rectHeight = rect.height;
    final double centerX = rect.left + rectWidth / 2;
    final double centerY = rect.top + rectHeight / 2;

    final double newWidth = rectWidth * (1 - widthReduction);
    final double newHeight = rectHeight * (1 + heightIncrease);

    // Handle front camera mirroring
    double left, right;
    if (cameraLensDirection == CameraLensDirection.front) {
      // Mirror horizontally for front camera
      left = widgetSize.width - ((centerX + newWidth / 2) * scale + offsetX);
      right = widgetSize.width - ((centerX - newWidth / 2) * scale + offsetX);
    } else {
      left = (centerX - newWidth / 2) * scale + offsetX;
      right = (centerX + newWidth / 2) * scale + offsetX;
    }

    return Rect.fromLTRB(
      left,
      (centerY - newHeight / 2) * scale + offsetY,
      right,
      (centerY + newHeight / 2) * scale + offsetY,
    );
  }

  Offset _scalePoint({
    required Point<int> point,
    required Size imageSize,
    required Size widgetSize,
  }) {
    // Calculate scale considering aspect ratio
    final double scaleX = widgetSize.width / imageSize.width;
    final double scaleY = widgetSize.height / imageSize.height;

    // Use the same scale for both dimensions
    final double scale = max(scaleX, scaleY);

    // Calculate offsets
    final double offsetX = (widgetSize.width - imageSize.width * scale) / 2;
    final double offsetY = (widgetSize.height - imageSize.height * scale) / 2;

    // Handle front camera mirroring
    double x;
    if (cameraLensDirection == CameraLensDirection.front) {
      x = widgetSize.width - (point.x.toDouble() * scale + offsetX);
    } else {
      x = point.x.toDouble() * scale + offsetX;
    }

    return Offset(
      x,
      point.y.toDouble() * scale + offsetY,
    );
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}