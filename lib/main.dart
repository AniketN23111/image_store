import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_store/api.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info/device_info.dart';
import 'package:geolocator/geolocator.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'api.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({Key? key, required this.camera}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraScreen(camera: camera),
    );
  }
}

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;
  const CameraScreen({Key? key, required this.camera}) : super(key: key);
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  List<String> _imagePaths = [];
  String? _latestImagePath;
  late DateTime? _latestImageTimestamp;
  late Timer _captureTimer;
  late String _deviceInfo;
  Position? _currentPosition;
  late String imagename;
  late Uint8List _imgebytes;
  late CloudApi api;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/clean-emblem-394910-905637ad42b3.json').then((json){
      api=CloudApi(json);
    });
    _controller = CameraController(widget.camera, ResolutionPreset.medium, enableAudio: false);
    _controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });

    _captureTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      _takePictureAndUpload();
    });
    _getDeviceInfo();
    _getLocation();
  }
  Future<Map<String, dynamic>> loadServiceAccountJson() async {
    String jsonString = await rootBundle.loadString('assets/clean-emblem-394910-905637ad42b3.json');
    return json.decode(jsonString);
  }

  Future<void> _takePictureAndUpload() async {
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures/flutter_app';
    await Directory(dirPath).create(recursive: true);

    if (_controller.value.isTakingPicture) {
      return null;
    }

    try {
      XFile picture = await _controller.takePicture();
      final File imageFile = File(picture.path);
      _imgebytes =imageFile.readAsBytesSync();
      final fileName = picture.path.split('/').last;

      // Upload the file to the bucket
      final response= await api.save(fileName, _imgebytes);
      print(response.downloadLink);

      setState(() {
        _imagePaths.add(picture.path);
        _latestImagePath = picture.path;
        _latestImageTimestamp = DateTime.now();
      });

    } catch (e) {
      print(e);
    }
  }

  Future<void> _getDeviceInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      setState(() {
        _deviceInfo = 'Android - ${androidInfo.model}';
      });
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      setState(() {
        _deviceInfo = 'iOS - ${iosInfo.model}';
      });
    }
  }

  Future<void> _getLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  Future<void> _downloadAndUpload() async {
    try {
      final Workbook workbook = Workbook();
      final Worksheet sheet = workbook.worksheets[0];

      sheet.getRangeByIndex(1, 1).setText("File Name");
      sheet.getRangeByIndex(1, 2).setText("Mobile Name");
      sheet.getRangeByIndex(1, 3).setText("Timestamp");
      sheet.getRangeByIndex(1, 4).setText("Location");

      // Write Mobile info, Timestamp, Location, and File Name for each image
      for (int i = 0; i < _imagePaths.length; i++) {
        sheet.getRangeByIndex(i + 2, 1).setText(_imagePaths[i].split('/').last);
        sheet.getRangeByIndex(i + 2, 2).setText(_deviceInfo); // Mobile info in column A
        sheet.getRangeByIndex(i + 2, 3).setText(_latestImageTimestamp?.toString() ?? ''); // Timestamp in column B
        sheet.getRangeByIndex(i + 2, 4).setText(_currentPosition?.toString() ?? ''); // Location in column C
        // File Name in column D
      }

      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final String path = (await getApplicationSupportDirectory()).path;
      final String fileName = '$path/Output.xlsx';
      final File file = File(fileName);
      await file.writeAsBytes(bytes, flush: true);

      // Upload images to Google Drive
      for (final imagePath in _imagePaths) {
        final imageFile = File(imagePath);
      }

      // Open the downloaded file
      OpenFile.open(fileName);

    } catch (e) {
      print('Error during download and upload: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Container();
    }
    return Scaffold(
      appBar: AppBar(title: Text('Auto Capture')),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Container(
              height: 500, // Adjust the height as needed
              child: CameraPreview(_controller),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: _downloadAndUpload,
                child: Text('Download Excel & Upload to Drive'),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                return _latestImagePath != null
                    ? Container(
                  padding: EdgeInsets.all(16.0),
                )
                    : Container();
              },
              childCount: 1,
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) {
                return _imagePaths.isNotEmpty
                    ? Container(
                  height: 100.0,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _imagePaths.length,
                    itemBuilder: (context, index) {
                      return Container(
                        margin: EdgeInsets.all(4.0),
                        child: Image.file(File(_imagePaths[index]), height: 80.0),
                      );
                    },
                  ),
                )
                    : Container();
              },
              childCount: 1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _captureTimer.cancel();
    _controller.dispose();
    super.dispose();
  }
}
