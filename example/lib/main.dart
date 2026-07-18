import 'dart:convert';

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
  const ExampleHomePage({super.key, this.initialUploadResponses = const []});

  /// Dữ liệu khởi tạo phục vụ demo/widget test; luồng thật tiếp tục nhận dữ
  /// liệu trực tiếp từ callback onImageUploaded.
  final List<Map<String, dynamic>> initialUploadResponses;

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<_UploadedImageItem> _uploadedImages = [];

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
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _uploadedImages.addAll(
      widget.initialUploadResponses.map(_UploadedImageItem.fromResponse),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AICycle On-Device Settings'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.tune), text: 'Cấu hình'),
            Tab(
              icon: const Icon(Icons.cloud_done_outlined),
              text: _uploadedImages.isEmpty
                  ? 'Ảnh đã tải'
                  : 'Ảnh đã tải (${_uploadedImages.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('General Configuration'),
                _textField('API Token', _apiTokenController, isRequired: true),
                _textField(
                  'Document ID',
                  _documentIdController,
                  isRequired: true,
                ),
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
                _textField(
                  'Manufacturing Year',
                  _mYearController,
                  isNumber: true,
                ),
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
          _buildUploadedImagesTab(),
        ],
      ),
    );
  }

  Widget _buildUploadedImagesTab() {
    if (_uploadedImages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 56, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Chưa có phản hồi upload',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 6),
              Text(
                'Ảnh tải thành công và lỗi từ onImageUploaded sẽ xuất hiện tại đây.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_uploadedImages.length} phản hồi upload',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(_uploadedImages.clear),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Xóa'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 320 ? 1 : 2;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemCount: _uploadedImages.length,
                itemBuilder: (context, index) =>
                    _buildUploadCard(_uploadedImages[index], index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUploadCard(_UploadedImageItem item, int index) {
    final imageUrl = item.imageUrl;
    if (item.errorText.isNotEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        color: const Color(0xFFFFF2F1),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imageUrl == null
                  ? const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 40,
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : const Center(
                                  child: CircularProgressIndicator(),
                                ),
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Text(
                                  'Không tải được ảnh từ URL',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                        ),
                        const Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.red,
                            child: Icon(
                              Icons.priority_high,
                              size: 15,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            Container(
              color: const Color(0xFFFFE3E1),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Text(
                item.errorText,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFC62828),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (imageUrl == null) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Không tải được ảnh từ URL',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 8,
                  right: 8,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: Color(0xFF22B968),
                    child: Icon(Icons.check, size: 15, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Text(
              item.label ?? 'Ảnh tải lên #${index + 1}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _handleImageUploaded(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() => _uploadedImages.add(_UploadedImageItem.fromResponse(data)));
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

  Future<void> _startSdk() async {
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

    final homeContext = context;
    var completionRequested = false;
    final cameraRoute = MaterialPageRoute<bool>(
      builder: (cameraContext) => AICycleOnDeviceCamera(
        aiCycleConfig: config,
        onImageUploaded: _handleImageUploaded,
        onComplete: () {
          if (!mounted || completionRequested) return;
          completionRequested = true;
          Navigator.of(cameraContext).pop(true);
        },
        onError: (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            homeContext,
          ).showSnackBar(SnackBar(content: Text('SDK Error: $error')));
        },
      ),
    );

    final completed = await Navigator.of(homeContext).push<bool>(cameraRoute);

    // Navigator.push hoàn tất ngay khi bắt đầu pop, còn Hero transition vẫn có
    // thể đang chạy. Chờ route được tháo hẳn rồi mới hiện SnackBar để không tạo
    // hai SnackBar Hero cùng tag giữa màn camera và màn chính.
    await cameraRoute.completed;
    if (!mounted || completed != true) return;

    _tabController.animateTo(1);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Completed')));
  }
}

class _UploadedImageItem {
  const _UploadedImageItem({
    required this.imageUrl,
    required this.errorText,
    this.label,
  });

  final String? imageUrl;
  final String errorText;
  final String? label;

  factory _UploadedImageItem.fromResponse(Map<String, dynamic> response) {
    final snapshot = Map<String, dynamic>.from(response);
    // VBI dùng data.imageRoot/imageAI; AICycle dùng result.imgUrl/imgDrawUrl.
    // Luôn ưu tiên URL ảnh gốc để phản ánh đúng ảnh người dùng đã chụp.
    final imageUrl =
        _findString(snapshot, const {'imageroot'}) ??
        _findString(snapshot, const {'imgurl'}) ??
        _findString(snapshot, const {
          'imageurl',
          'imagedrawurl',
          'urlimage',
          'linkimage',
        }) ??
        _findString(snapshot, const {'imageai'}) ??
        _findString(snapshot, const {'imgdrawurl'});
    final imageId = _findString(snapshot, const {'imageid'});
    final label =
        _findString(snapshot, const {
          'imagename',
          'filename',
          'label',
          'partname',
          'tenhangmuc',
          'additionalcornerinfor',
        }) ??
        (imageId == null ? null : 'Ảnh #$imageId');
    final hasError = _hasErrorStatus(snapshot) || imageUrl == null;
    return _UploadedImageItem(
      imageUrl: imageUrl,
      label: label,
      errorText: hasError ? _errorText(snapshot) : '',
    );
  }

  static bool _hasErrorStatus(Map<String, dynamic> response) {
    final typeResponse = _findString(response, const {
      'typeresponse',
    })?.toUpperCase();
    if (typeResponse == 'ERROR' || typeResponse == 'FAILED') return true;

    final errorLevel = _findString(response, const {
      'errorlevel',
    })?.toLowerCase();
    if (errorLevel == 'error' ||
        errorLevel == 'failed' ||
        errorLevel == 'failure') {
      return true;
    }

    final isPhotoValid = _findString(response, const {
      'isphotovalid',
    })?.toLowerCase();
    if (isPhotoValid == 'false') return true;

    final errorCode = int.tryParse(
      _findString(response, const {'errorcodefromengine'}) ?? '',
    );
    if (errorCode != null && errorCode != 0) return true;

    final statusText =
        _findString(response, const {'status'}) ??
        _findString(response, const {'statuscode'});
    final normalizedStatus = statusText?.toLowerCase();
    if (normalizedStatus == 'error' ||
        normalizedStatus == 'failed' ||
        normalizedStatus == 'failure') {
      return true;
    }

    final numericStatus = int.tryParse(statusText ?? '');
    return numericStatus != null &&
        (numericStatus < 200 || numericStatus >= 300);
  }

  static String _errorText(Map<String, dynamic> response) {
    final message =
        _findValue(response, const {
          'errormessage',
          'error',
          'message',
          'description',
        }) ??
        _findValue(response, const {'errorcodefromengine'}) ??
        _findValue(response, const {'rawbody', 'responsebody'});
    final statusCode =
        _findValue(response, const {'status'}) ??
        _findValue(response, const {'statuscode'});
    final prefix = statusCode == null ? '' : 'HTTP $statusCode: ';
    if (message != null) return '$prefix${_displayValue(message)}';
    return '$prefix${_displayValue(response)}';
  }

  static String? _findString(Object? node, Set<String> keys) {
    final value = _findValue(node, keys);
    if (value == null) return null;
    final string = value.toString().trim();
    return string.isEmpty ? null : string;
  }

  static Object? _findValue(Object? node, Set<String> keys) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (keys.contains(_normalizeKey(entry.key.toString()))) {
          final value = entry.value;
          if (value != null && value.toString().trim().isNotEmpty) return value;
        }
      }
      for (final value in node.values) {
        final found = _findValue(value, keys);
        if (found != null) return found;
      }
    } else if (node is Iterable) {
      for (final value in node) {
        final found = _findValue(value, keys);
        if (found != null) return found;
      }
    } else if (node is String) {
      final value = node.trim();
      final looksLikeJson =
          (value.startsWith('{') && value.endsWith('}')) ||
          (value.startsWith('[') && value.endsWith(']'));
      if (looksLikeJson) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map || decoded is Iterable) {
            return _findValue(decoded, keys);
          }
        } catch (_) {
          // Đây có thể chỉ là text lỗi thông thường, không phải JSON lồng.
        }
      }
    }
    return null;
  }

  static String _normalizeKey(String key) =>
      key.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();

  static String _displayValue(Object value) {
    if (value is String) return value;
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
