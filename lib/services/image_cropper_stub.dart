// Stub for image_cropper on web
class ImageCropper {
  Future<dynamic> cropImage({
    required String sourcePath,
    List<dynamic>? aspectRatioPresets,
    dynamic compressFormat,
    int? compressQuality,
  }) async {
    return null;
  }
}

enum CropAspectRatioPreset {
  square,
  ratio4x3,
}

enum ImageCompressFormat {
  jpg,
  png,
}

