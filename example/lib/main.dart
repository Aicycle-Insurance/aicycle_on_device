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
  final _documentIdController = TextEditingController(text: 'doc-example-001');
  final _documentNameController = TextEditingController(text: 'Test Claim');
  AiCycleEnvironment _environment = AiCycleEnvironment.stage;
  AiCycleOrg _organization = AiCycleOrg.aicycle;
  bool _loggingEnabled = true;

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
  final _confidenceController = TextEditingController(text: '0.25');
  final _iouController = TextEditingController(text: '0.45');

  // Display Config
  bool _showBackButton = true;

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
              'Confidence Threshold (0.0 - 1.0)',
              _confidenceController,
              isNumber: true,
            ),
            _textField(
              'IOU Threshold (0.0 - 1.0)',
              _iouController,
              isNumber: true,
            ),

            const Divider(height: 32),
            _sectionTitle('Display Configuration'),
            _switchTile(
              'Show Back Button',
              _showBackButton,
              (val) => setState(() => _showBackButton = val),
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

    final config = AICycleConfig(
      generalConfig: GeneralConfig(
        apiToken: _apiTokenController.text,
        documentId: _documentIdController.text,
        documentName: _documentNameController.text,
        environment: _environment,
        organization: _organization,
        loggingEnabled: _loggingEnabled,
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
        confidenceThreshold: double.tryParse(_confidenceController.text),
        iouThreshold: double.tryParse(_iouController.text),
      ),
      displayConfig: DisplayConfig(showBackButton: _showBackButton),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AICycleOnDevice(
          aiCycleConfig: config,
          onComplete: (data) {
            if (data is Map<AiModelType, DownloadedModelInfo>) {
              _showSelectedModels(data);
            }
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

  void _showSelectedModels(Map<AiModelType, DownloadedModelInfo> models) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Model đã chọn'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in models.entries) ...[
              Text(
                entry.key.displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'v${entry.value.version}\n${entry.value.filePath}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
