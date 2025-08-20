import 'package:image_picker/image_picker.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

Future<XFile?> safePickImage({bool useCamera = false}) async {
  final picker = ImagePicker();
  if (useCamera) {
    final supports = await ImagePickerPlatform.instance.supportsImageSource(ImageSource.camera);
    if (!supports) {
      return picker.pickImage(source: ImageSource.gallery);
    }
  }
  return picker.pickImage(source: useCamera ? ImageSource.camera : ImageSource.gallery);
}
