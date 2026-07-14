import 'package:aicycle_on_device/aicycle_on_device.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AICycle On-Device Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F2738)),
        useMaterial3: true,
      ),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  // General Config
  final _apiTokenController = TextEditingController(text: '');
  final _documentIdController = TextEditingController(text: '');
  final _documentNameController = TextEditingController(text: 'Test Claim');
  final _customDomainController = TextEditingController(
    text: 'https://stage.api.aicycle.ai',
  );
  AiCycleEnvironment _environment = AiCycleEnvironment.stage;
  AiCycleOrg _organization = AiCycleOrg.aicycle;
  bool _loggingEnabled = true;
  bool _savePhoto = true;
  bool _alwaysCache = false;

  // Car Information
  final _companyNameController = TextEditingController(text: 'toyota');
  final _modelNameController = TextEditingController(text: 'vios');
  final _mYearController = TextEditingController(text: '2022');
  final _vVersionController = TextEditingController(text: '1.5C');
  final _lPlateController = TextEditingController(text: '30A12345');
  final _vTypeController = TextEditingController(text: 'sedan');
  final _colorController = TextEditingController(text: '#A2A8A1');
  final _garageIdController = TextEditingController(text: '');
  final _vehicleBrandIdController = TextEditingController(text: '');

  // Model Config
  // Ngưỡng riêng cho từng model (để trống = dùng mặc định của SDK).
  final _carPartConfController = TextEditingController(text: '0.5');
  final _carPartIouController = TextEditingController(text: '0.45');
  final _carCornerConfController = TextEditingController(text: '0.3');
  final _carDamageConfController = TextEditingController(text: '0.3');
  final _carDamageIouController = TextEditingController(text: '0.45');
  final _licensePlateConfController = TextEditingController(text: '0.5');

  // VBI Config (chỉ bắt buộc khi Organization = vbi)
  final _vbiApiVersionCodeController = TextEditingController(text: 'v1');
  final _vbiApiUploadBaseUrlController = TextEditingController(text: '');
  final _vbiAuthorityIdController = TextEditingController(text: '');
  final _vbiSignatureKeyController = TextEditingController(text: '');
  final _vbiExternalSessionIdController = TextEditingController(text: '');
  final _vbiJobIdController = TextEditingController(text: '');
  final _vbiMaHangMucController = TextEditingController(text: '');
  final _vbiTenHangMucController = TextEditingController(text: 'Ảnh toàn cảnh');
  final _vbiDepartmentIdController = TextEditingController(text: '000');
  final _vbiUserIdController = TextEditingController(text: '');
  final _vbiMaTVVController = TextEditingController(text: '');
  final _vbiSourceController = TextEditingController(text: '');

  // Display Config
  bool _showBackButton = true;

  // Validate Config
  bool _require4AnglePanoramicPhotos = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AICycle On-Device Settings'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('General Configuration'),
            _textField('API Token', _apiTokenController, isRequired: true),
            _textField('Document ID', _documentIdController, isRequired: true),
            _textField('Document Name', _documentNameController),
            _textField('Custom Domain', _customDomainController),
            _dropdown<AiCycleEnvironment>(
              'Environment',
              _environment,
              AiCycleEnvironment.values,
              (val) => setState(() => _environment = val!),
            ),
            _dropdown<AiCycleOrg>(
              'Organization',
              _organization,
              AiCycleOrg.values,
              (val) => setState(() => _organization = val!),
              isRequired: true,
            ),
            _switchTile(
              'Enable Logging',
              _loggingEnabled,
              (val) => setState(() => _loggingEnabled = val),
            ),
            _switchTile(
              'Save Photo',
              _savePhoto,
              (val) => setState(() => _savePhoto = val),
            ),
            _switchTile(
              'Always Cache',
              _alwaysCache,
              (val) => setState(() => _alwaysCache = val),
            ),

            if (_organization == AiCycleOrg.vbi) ...[
              const Divider(height: 32),
              _sectionTitle('VBI Configuration'),
              _textField(
                'API Version Code',
                _vbiApiVersionCodeController,
                isRequired: true,
              ),
              _textField(
                'API Upload Base URL',
                _vbiApiUploadBaseUrlController,
                isRequired: true,
              ),
              _textField(
                'Authority ID',
                _vbiAuthorityIdController,
                isRequired: true,
              ),
              _textField(
                'Signature Key',
                _vbiSignatureKeyController,
                isRequired: true,
              ),
              _textField(
                'External Session ID',
                _vbiExternalSessionIdController,
                isRequired: true,
              ),
              _textField('Job ID', _vbiJobIdController, isRequired: true),
              _textField(
                'Mã hạng mục',
                _vbiMaHangMucController,
                isRequired: true,
              ),
              _textField(
                'Tên hạng mục',
                _vbiTenHangMucController,
                isRequired: true,
              ),
              _textField(
                'Department ID',
                _vbiDepartmentIdController,
                isRequired: true,
              ),
              _textField('User ID', _vbiUserIdController, isRequired: true),
              _textField('Mã TVV', _vbiMaTVVController, isRequired: true),
              _textField('Source', _vbiSourceController, isRequired: true),
            ],

            const Divider(height: 32),
            _sectionTitle('Car Information'),
            _textField('Company Name', _companyNameController),
            _textField('Model Name', _modelNameController),
            _textField('Manufacturing Year', _mYearController, isNumber: true),
            _textField('Vehicle Version', _vVersionController),
            _textField('License Plate', _lPlateController),
            _textField('Vehicle Type', _vTypeController),
            _textField('Color (Hex, e.g., #FFFFFF)', _colorController),
            _textField('Garage ID', _garageIdController),
            _textField('Vehicle Brand ID', _vehicleBrandIdController),

            const Divider(height: 32),
            _sectionTitle('Model Configuration'),
            _textField(
              'Car Part Conf Threshold (0.0 - 1.0)',
              _carPartConfController,
              isNumber: true,
            ),
            _textField(
              'Car Part IOU Threshold (0.0 - 1.0)',
              _carPartIouController,
              isNumber: true,
            ),
            _textField(
              'Car Corner Conf Threshold (0.0 - 1.0)',
              _carCornerConfController,
              isNumber: true,
            ),
            _textField(
              'Car Damage Conf Threshold (0.0 - 1.0)',
              _carDamageConfController,
              isNumber: true,
            ),
            _textField(
              'Car Damage IOU Threshold (0.0 - 1.0)',
              _carDamageIouController,
              isNumber: true,
            ),
            _textField(
              'License Plate OCR Conf Threshold (0.0 - 1.0)',
              _licensePlateConfController,
              isNumber: true,
            ),

            const Divider(height: 32),
            _sectionTitle('Display Configuration'),
            _switchTile(
              'Show Back Button',
              _showBackButton,
              (val) => setState(() => _showBackButton = val),
            ),

            const Divider(height: 32),
            _sectionTitle('Validate Configuration'),
            _switchTile(
              'Require 4-angle panoramic photos',
              _require4AnglePanoramicPhotos,
              (val) => setState(() => _require4AnglePanoramicPhotos = val),
            ),

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _startSdk,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: const Color(0xFF1F2738),
                foregroundColor: Colors.white,
              ),
              child: const Text('START AI INSPECTION'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    bool isRequired = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          label: isRequired ? _richLabel(label) : Text(label),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> items,
    ValueChanged<T?> onChanged, {
    bool isRequired = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          label: isRequired ? _richLabel(label) : Text(label),
          border: const OutlineInputBorder(),
        ),
        items: items.map((T item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(item.toString().split('.').last),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _richLabel(String label) {
    return RichText(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black54, fontSize: 16),
        children: const [
          TextSpan(
            text: ' *',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _switchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  void _startSdk() {
    if (_apiTokenController.text.isEmpty ||
        _documentIdController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    VBIConfig? vbiConfig;
    if (_organization == AiCycleOrg.vbi) {
      if (_vbiApiVersionCodeController.text.isEmpty ||
          _vbiApiUploadBaseUrlController.text.isEmpty ||
          _vbiAuthorityIdController.text.isEmpty ||
          _vbiSignatureKeyController.text.isEmpty ||
          _vbiExternalSessionIdController.text.isEmpty ||
          _vbiJobIdController.text.isEmpty ||
          _vbiMaHangMucController.text.isEmpty ||
          _vbiTenHangMucController.text.isEmpty ||
          _vbiDepartmentIdController.text.isEmpty ||
          _vbiUserIdController.text.isEmpty ||
          _vbiMaTVVController.text.isEmpty ||
          _vbiSourceController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all required VBI fields')),
        );
        return;
      }
      vbiConfig = VBIConfig(
        apiVersionCode: _vbiApiVersionCodeController.text,
        apiUploadBaseUrl: _vbiApiUploadBaseUrlController.text,
        authorityId: _vbiAuthorityIdController.text,
        signatureKey: _vbiSignatureKeyController.text,
        externalSessionId: _vbiExternalSessionIdController.text,
        jobId: _vbiJobIdController.text,
        maHangMuc: _vbiMaHangMucController.text,
        tenHangMuc: _vbiTenHangMucController.text,
        departmentId: _vbiDepartmentIdController.text,
        userId: _vbiUserIdController.text,
        maTVV: _vbiMaTVVController.text,
        source: _vbiSourceController.text,
      );
    }

    final config = AICycleConfig(
      generalConfig: GeneralConfig(
        apiToken: _apiTokenController.text,
        documentId: _documentIdController.text,
        documentName: _documentNameController.text,
        environment: _environment,
        organization: _organization,
        loggingEnabled: _loggingEnabled,
        savePhotoAfterShot: _savePhoto,
        alwaysCache: _alwaysCache,
        aicBaseUrl: _customDomainController.text.isEmpty
            ? null
            : _customDomainController.text,
      ),
      carInformation: CarInformation(
        companyName: _companyNameController.text,
        modelName: _modelNameController.text,
        manufacturingYear: int.tryParse(_mYearController.text),
        vehicleVersionName: _vVersionController.text,
        licensePlate: _lPlateController.text,
        vehicleType: _vTypeController.text,
        color: _colorController.text,
        garageId: _garageIdController.text,
        vehicleBrandId: _vehicleBrandIdController.text,
      ),
      modelConfig: ModelConfig(
        carPartConfThreshold: double.parse(_carPartConfController.text),
        carPartIouThreshold: double.parse(_carPartIouController.text),
        carCornerConfThreshold: double.parse(_carCornerConfController.text),
        carDamageConfThreshold: double.parse(_carDamageConfController.text),
        carDamageIouThreshold: double.parse(_carDamageIouController.text),
        licensePlateConfThreshold: double.parse(
          _licensePlateConfController.text,
        ),
      ),
      displayConfig: DisplayConfig(showBackButton: _showBackButton),
      validateConfig: ValidateConfig(
        require4AnglePanoramicPhotos: _require4AnglePanoramicPhotos,
      ),
      vbiConfig: vbiConfig,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AICycleOnDeviceCamera(
          aiCycleConfig: config,
          onImageUploaded: (data) {
            // print(data);
          },
          onComplete: () {
            if (mounted) Navigator.pop(context);
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Completed')));
          },
          onError: (error) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('SDK Error: $error')));
          },
        ),
      ),
    );
  }
}
