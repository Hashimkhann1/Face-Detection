# Face Detection App

A real-time face detection application built with Flutter and Google ML Kit.

## Features

- **Multi-Face Detection** - Detect multiple faces simultaneously
- **Color-Coded Tracking** - Each face gets a unique color
- **Smile Detection** - Shows smile probability indicators
- **Face Numbering** - Circular badges to identify each face
- **Facial Landmarks** - Marks eyes, nose, and mouth positions
- **Rounded Boxes** - Modern UI with smooth corners

## Setup

1. Clone the repository
2. Run `flutter pub get`
3. Run on a physical device: `flutter run`

The app is ready to run on both Android and iOS.

## Requirements

- Flutter SDK
- Physical device with camera
- Camera permissions (automatically requested)

## Technical Details

- **Resolution**: Medium preset for optimal performance
- **Detection Mode**: Fast mode for real-time processing
- **Camera**: Front-facing camera with proper mirroring
- **ML Kit**: Face detection with landmarks and classification
