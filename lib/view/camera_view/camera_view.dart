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
      performanceMode: FaceDetectorMode.fast, // Use fast mode
    );
    faceDetector = FaceDetector(options: options);
  }

  void cameraInitialize() async {
    try {
      _cameras = await availableCameras();

      // Use front camera
      cameraController = CameraController(
        _cameras[1],
        ResolutionPreset.low,
        enableAudio: false,
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

      // Format check
      final format = cameraImage.format.group;

      // Only process if format is correct
      if (format != ImageFormatGroup.yuv420 &&
          format != ImageFormatGroup.nv21) {
        print('Unsupported format: ${cameraImage.format.raw}');
        return null;
      }

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
        format: InputImageFormat.nv21, // Use NV21
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
        title: const Text('Face Detection',style: TextStyle(fontWeight: FontWeight.bold),),
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
                    'Faces: ${detectedFaces.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (detectedFaces.isNotEmpty)
                    Text(
                      'Processing...',
                      style: const TextStyle(
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

  FacePainter({required this.faces, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    final Paint landmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red;

    for (final face in faces) {
      final rect = _scaleRect(
        rect: face.boundingBox,
        imageSize: imageSize,
        widgetSize: size,
      );
      canvas.drawRect(rect, paint);

      // Draw landmarks
      _drawLandmark(canvas, face, FaceLandmarkType.leftEye, landmarkPaint, imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.rightEye, landmarkPaint, imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.noseBase, landmarkPaint, imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.leftMouth, landmarkPaint, imageSize, size);
      _drawLandmark(canvas, face, FaceLandmarkType.rightMouth, landmarkPaint, imageSize, size);
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
    final scaleX = widgetSize.width / imageSize.width;
    final scaleY = widgetSize.height / imageSize.height;

    return Rect.fromLTRB(
      rect.left * scaleX,
      rect.top * scaleY,
      rect.right * scaleX,
      rect.bottom * scaleY,
    );
  }

  Offset _scalePoint({
    required Point<int> point,
    required Size imageSize,
    required Size widgetSize,
  }) {
    final scaleX = widgetSize.width / imageSize.width;
    final scaleY = widgetSize.height / imageSize.height;

    return Offset(
      point.x.toDouble() * scaleX,
      point.y.toDouble() * scaleY,
    );
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}