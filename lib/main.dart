import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MicrostockApp());

const supportedExtensions = {'jpg', 'jpeg', 'jfif', 'png', 'webp'};
const categories = [
  'Animals',
  'Architecture',
  'Backgrounds/Textures',
  'Beauty/Fashion',
  'Business/Finance',
  'Education',
  'Food and Drink',
  'Healthcare/Medical',
  'Holidays',
  'Industrial',
  'Landscape/Nature',
  'Lifestyle',
  'People',
  'Religion',
  'Science/Technology',
  'Sports',
  'Transportation',
  'Travel',
  'Vintage',
  'Abstract',
];

const defaultPrompt = '''You are an expert microstock image metadata generator.

Analyze the image and create high-quality metadata suitable for stock image platforms.
Return valid JSON only. Do not include markdown or explanation.

Rules:
1. Use English.
2. Create a clear, searchable title.
3. Create a natural description.
4. Generate 30 to 50 relevant keywords.
5. Sort keywords from most important to least important.
6. Avoid trademarks, brand names, copyrighted characters, artist names, or celebrity names.
7. Suggest one category from the provided category list.
8. Add warnings if the image may require model release, property release, or editorial use.
9. If the image appears AI-generated, set ai_generated to true.

Category list:
Animals, Architecture, Backgrounds/Textures, Beauty/Fashion, Business/Finance, Education, Food and Drink, Healthcare/Medical, Holidays, Industrial, Landscape/Nature, Lifestyle, People, Religion, Science/Technology, Sports, Transportation, Travel, Vintage, Abstract.

Output format:
{
  "title": "",
  "description": "",
  "keywords": [],
  "category": "",
  "editorial": false,
  "commercial_use": true,
  "ai_generated": false,
  "warnings": []
}''';

class MicrostockApp extends StatelessWidget {
  const MicrostockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Microstock Metadata AI',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff60a5fa),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final storage = LocalStorage();
  final importPathCtrl = TextEditingController();
  final fileNameCtrl = TextEditingController();
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final keywordsCtrl = TextEditingController();
  final baseUrlCtrl = TextEditingController();
  final apiKeyCtrl = TextEditingController();
  final modelCtrl = TextEditingController(text: 'gpt-5.5');
  final timeoutCtrl = TextEditingController(text: '120');
  final retryCtrl = TextEditingController(text: '2');
  final keywordLimitCtrl = TextEditingController(text: '50');
  final promptCtrl = TextEditingController(text: defaultPrompt);

  AppState state = AppState.empty();
  int selected = -1;
  String category = categories.first;
  String log = 'Ready.';
  bool batchRunning = false;
  bool stopBatch = false;

  ImageItem? get current => selected >= 0 && selected < state.images.length ? state.images[selected] : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [importPathCtrl, fileNameCtrl, titleCtrl, descCtrl, keywordsCtrl, baseUrlCtrl, apiKeyCtrl, modelCtrl, timeoutCtrl, retryCtrl, keywordLimitCtrl, promptCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final loaded = await storage.load();
    setState(() {
      state = loaded;
      baseUrlCtrl.text = loaded.settings.baseUrl;
      apiKeyCtrl.text = loaded.settings.apiKey;
      modelCtrl.text = loaded.settings.model;
      timeoutCtrl.text = '${loaded.settings.timeoutSeconds}';
      retryCtrl.text = '${loaded.settings.maxRetries}';
      keywordLimitCtrl.text = '${loaded.settings.keywordLimit}';
      promptCtrl.text = loaded.settings.prompt.isEmpty ? defaultPrompt : loaded.settings.prompt;
      if (state.images.isNotEmpty) {
        selected = 0;
        _fillEditor(state.images.first);
      }
    });
  }

  AppSettings _settings() => AppSettings(
        baseUrl: baseUrlCtrl.text.trim(),
        apiKey: apiKeyCtrl.text.trim(),
        model: modelCtrl.text.trim().isEmpty ? 'gpt-5.5' : modelCtrl.text.trim(),
        timeoutSeconds: int.tryParse(timeoutCtrl.text) ?? 120,
        maxRetries: int.tryParse(retryCtrl.text) ?? 2,
        keywordLimit: int.tryParse(keywordLimitCtrl.text) ?? 50,
        prompt: promptCtrl.text.trim().isEmpty ? defaultPrompt : promptCtrl.text,
      );

  Future<void> _persist() async {
    await storage.save(state.copyWith(settings: _settings()));
    setState(() => log = 'Settings and library saved.');
  }

  void _fillEditor(ImageItem image) {
    fileNameCtrl.text = image.fileName;
    titleCtrl.text = image.metadata.title;
    descCtrl.text = image.metadata.description;
    keywordsCtrl.text = image.metadata.keywords.join(', ');
    category = categories.contains(image.metadata.category) ? image.metadata.category : categories.first;
  }

  void _saveEditor({bool markEdited = false}) {
    final image = current;
    if (image == null) return;
    final updated = image.copyWith(
      status: markEdited ? ImageStatus.edited : image.status,
      metadata: image.metadata.copyWith(
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim(),
        keywords: parseKeywords(keywordsCtrl.text),
        category: category,
      ),
      updatedAt: DateTime.now(),
    );
    _replace(updated);
  }

  void _replace(ImageItem image) {
    final next = [...state.images];
    final index = next.indexWhere((i) => i.filePath == image.filePath);
    if (index >= 0) {
      next[index] = image;
      state = state.copyWith(images: next);
    }
  }

  Future<void> _importFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: supportedExtensions.toList(),
      );
      if (result == null) return;
      await _addPaths(result.paths.whereType<String>());
    } catch (e) {
      setState(() => log = 'Dialog import gagal: $e. Gunakan Import Path atau install zenity/kdialog.');
    }
  }

  Future<void> _importFolder() async {
    try {
      final folder = await FilePicker.platform.getDirectoryPath();
      if (folder == null) return;
      await _addDirectory(folder);
    } catch (e) {
      setState(() => log = 'Dialog folder gagal: $e. Gunakan Import Path atau install zenity/kdialog.');
    }
  }

  Future<void> _importManualPath() async {
    final rawPath = importPathCtrl.text.trim();
    if (rawPath.isEmpty) {
      setState(() => log = 'Isi path file atau folder terlebih dahulu.');
      return;
    }
    final path = rawPath.replaceFirst(RegExp(r'^file://'), '');
    final fileType = await FileSystemEntity.type(path);
    if (fileType == FileSystemEntityType.file) {
      await _addPaths([path]);
    } else if (fileType == FileSystemEntityType.directory) {
      await _addDirectory(path);
    } else {
      setState(() => log = 'Path tidak ditemukan: $path');
    }
  }

  Future<void> _addDirectory(String folder) async {
    try {
      await _addPaths(Directory(folder).listSync(recursive: true).whereType<File>().map((f) => f.path));
    } catch (e) {
      setState(() => log = 'Gagal membaca folder: $e');
    }
  }

  Future<void> _addPaths(Iterable<String> paths) async {
    final existing = state.images.map((i) => i.filePath).toSet();
    final images = [...state.images];
    var added = 0;
    var skipped = 0;
    var duplicate = 0;
    var unsupported = 0;
    var missing = 0;
    var failed = 0;
    final unsupportedExts = <String>{};
    for (final path in paths) {
      try {
        final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
        if (!supportedExtensions.contains(ext)) {
          unsupported++;
          unsupportedExts.add(ext.isEmpty ? '(no extension)' : '.$ext');
          skipped++;
          continue;
        }
        if (existing.contains(path)) {
          duplicate++;
          skipped++;
          continue;
        }
        final file = File(path);
        if (!await file.exists()) {
          missing++;
          skipped++;
          continue;
        }
        final resolution = await readResolution(file);
        images.add(ImageItem(
          filePath: path,
          fileName: p.basename(path),
          width: resolution.$1,
          height: resolution.$2,
          fileSize: await file.length(),
          status: ImageStatus.pending,
          metadata: ImageMetadata.empty(),
          updatedAt: DateTime.now(),
        ));
        existing.add(path);
        added++;
      } catch (_) {
        failed++;
        skipped++;
      }
    }
    setState(() {
      state = state.copyWith(images: images);
      if (selected == -1 && images.isNotEmpty) {
        selected = 0;
        _fillEditor(images.first);
      }
      final details = [
        if (duplicate > 0) 'duplicate $duplicate',
        if (unsupported > 0) 'unsupported $unsupported ${unsupportedExts.join(', ')}',
        if (missing > 0) 'missing $missing',
        if (failed > 0) 'error $failed',
      ].join('; ');
      log = 'Imported $added image(s), skipped $skipped file(s)${details.isEmpty ? '' : ': $details'}.';
    });
    await storage.save(state.copyWith(settings: _settings()));
  }

  Future<void> _testApi() async {
    try {
      await AiClient(_settings()).testConnection();
      await storage.save(state.copyWith(settings: _settings()));
      setState(() => log = 'Koneksi API berhasil.');
    } catch (e) {
      setState(() => log = 'Koneksi API gagal: $e');
    }
  }

  Future<void> _generateCurrent() async {
    _saveEditor();
    final image = current;
    if (image == null) return;
    await _generate(image, syncEditor: true);
  }

  Future<void> _generate(ImageItem image, {required bool syncEditor}) async {
    final settings = _settings();
    if (settings.baseUrl.isEmpty) {
      setState(() => log = 'Isi Base URL API terlebih dahulu.');
      return;
    }
    setState(() {
      _replace(image.copyWith(status: ImageStatus.processing));
      log = 'Generating ${image.fileName}...';
    });
    try {
      final metadata = await AiClient(settings).generate(image.filePath, image.fileName);
      final status = validateMetadata(metadata, settings.keywordLimit).isEmpty ? ImageStatus.success : ImageStatus.review;
      final updated = image.copyWith(status: status, metadata: metadata, updatedAt: DateTime.now());
      setState(() {
        _replace(updated);
        if (syncEditor && current?.filePath == image.filePath) _fillEditor(updated);
        log = 'Generated ${image.fileName}.';
      });
    } catch (e) {
      setState(() {
        _replace(image.copyWith(status: ImageStatus.failed, metadata: image.metadata.copyWith(warnings: ['$e']), updatedAt: DateTime.now()));
        log = 'Failed ${image.fileName}: $e';
      });
    }
    await storage.save(state.copyWith(settings: settings));
  }

  Future<void> _batch() async {
    if (batchRunning) return;
    _saveEditor();
    setState(() {
      batchRunning = true;
      stopBatch = false;
    });
    final queue = state.images.where((i) => i.status != ImageStatus.success).toList();
    for (var i = 0; i < queue.length; i++) {
      if (stopBatch) break;
      setState(() => log = 'Batch ${i + 1}/${queue.length}: ${queue[i].fileName}');
      await _generate(queue[i], syncEditor: current?.filePath == queue[i].filePath);
    }
    setState(() {
      batchRunning = false;
      log = stopBatch ? 'Batch stopped.' : 'Batch finished.';
    });
  }

  Future<void> _retryFailed() async {
    if (batchRunning) return;
    setState(() => batchRunning = true);
    final failed = state.images.where((i) => i.status == ImageStatus.failed).toList();
    for (final image in failed) {
      if (stopBatch) break;
      await _generate(image, syncEditor: current?.filePath == image.filePath);
    }
    setState(() {
      batchRunning = false;
      log = 'Retry failed finished.';
    });
  }

  Future<void> _batchRenameFiles() async {
    if (batchRunning) return;
    _saveEditor();
    setState(() {
      batchRunning = true;
      stopBatch = false;
      log = 'Batch rename started.';
    });
    var renamed = 0;
    var skipped = 0;
    final images = [...state.images];
    for (var i = 0; i < images.length; i++) {
      if (stopBatch) break;
      final image = images[i];
      final slug = slugFileName(image.metadata.title);
      if (slug.isEmpty || !await File(image.filePath).exists()) {
        skipped++;
        continue;
      }
      final ext = p.extension(image.fileName);
      final outputDir = await outputDirectoryFor(image.filePath);
      final targetPath = await uniqueFilePath(outputDir.path, slug, ext, image.filePath);
      if (targetPath == image.filePath) {
        skipped++;
        continue;
      }
      try {
        final renamedFile = await moveOrCopyToOutput(image.filePath, targetPath);
        images[i] = image.copyWith(
          filePath: renamedFile.path,
          fileName: p.basename(renamedFile.path),
          fileSize: await renamedFile.length(),
          updatedAt: DateTime.now(),
        );
        renamed++;
        setState(() => log = 'Output renamed $renamed file(s): ${images[i].fileName}');
      } catch (_) {
        skipped++;
      }
    }
    setState(() {
      state = state.copyWith(images: images);
      if (current != null) _fillEditor(current!);
      batchRunning = false;
      log = stopBatch ? 'Batch rename stopped. Changed $renamed, skipped $skipped.' : 'Batch rename finished. Changed $renamed, skipped $skipped.';
    });
    await storage.save(state.copyWith(settings: _settings()));
  }

  Future<void> _batchWriteMetadataToFiles() async {
    if (batchRunning) return;
    _saveEditor();
    setState(() {
      batchRunning = true;
      stopBatch = false;
      log = 'Batch write metadata started.';
    });
    var written = 0;
    var skipped = 0;
    String? lastError;
    final maxKeywords = _settings().keywordLimit;
    final images = [...state.images];
    for (var i = 0; i < images.length; i++) {
      if (stopBatch) break;
      final image = images[i];
      final errors = validateMetadata(image.metadata, maxKeywords);
      if (errors.isNotEmpty) {
        skipped++;
        continue;
      }
      try {
        final outputImage = await copyImageToOutput(image);
        await MetadataFileWriter.write(outputImage);
        images[i] = outputImage;
        written++;
        setState(() => log = 'Wrote metadata $written file(s): ${outputImage.fileName}');
      } catch (e) {
        skipped++;
        lastError = '$e';
        if (lastError.contains('exiftool tidak ditemukan')) break;
      }
    }
    setState(() {
      state = state.copyWith(images: images);
      if (current != null) _fillEditor(current!);
      batchRunning = false;
      log = stopBatch
          ? 'Batch write stopped. Written $written, skipped $skipped.'
          : lastError == null
              ? 'Batch write finished. Written $written, skipped $skipped.'
              : 'Batch write finished. Written $written, skipped $skipped. Error: $lastError';
    });
    await storage.save(state.copyWith(settings: _settings()));
  }

  Future<void> _saveMetadata() async {
    _saveEditor(markEdited: true);
    await storage.save(state.copyWith(settings: _settings()));
    setState(() => log = validateMetadata(current!.metadata, _settings().keywordLimit).isEmpty ? 'Metadata saved.' : 'Metadata saved, perlu review validasi.');
  }

  Future<void> _renameCurrentFile() async {
    final image = current;
    if (image == null) return;
    var requestedName = fileNameCtrl.text.trim();
    if (requestedName.isEmpty) {
      requestedName = slugFileName(titleCtrl.text);
    }
    if (requestedName.contains('/') || requestedName.contains('\\')) {
      setState(() => log = 'Nama file tidak boleh berisi pemisah folder.');
      return;
    }
    final oldExt = p.extension(image.fileName);
    if (requestedName == image.fileName && titleCtrl.text.trim().isNotEmpty) {
      requestedName = slugFileName(titleCtrl.text);
    }
    if (requestedName.isEmpty) {
      setState(() => log = 'Isi Filename atau Title terlebih dahulu.');
      return;
    }
    final newName = p.extension(requestedName).isEmpty ? '$requestedName$oldExt' : requestedName;
    final newExt = p.extension(newName).replaceFirst('.', '').toLowerCase();
    if (!supportedExtensions.contains(newExt)) {
      setState(() => log = 'Ekstensi file tidak didukung: .$newExt');
      return;
    }
    try {
      final outputDir = await outputDirectoryFor(image.filePath);
      final baseName = p.basenameWithoutExtension(newName);
      final targetPath = await uniqueFilePath(outputDir.path, baseName, p.extension(newName), image.filePath);
      if (targetPath == image.filePath) {
        setState(() => log = 'Nama output tidak berubah. Edit Filename atau Title dulu.');
        return;
      }
      final renamed = await moveOrCopyToOutput(image.filePath, targetPath);
      final updated = image.copyWith(
        filePath: renamed.path,
        fileName: p.basename(renamed.path),
        fileSize: await renamed.length(),
        updatedAt: DateTime.now(),
      );
      final next = [...state.images];
      next[selected] = updated;
      setState(() {
        state = state.copyWith(images: next);
        fileNameCtrl.text = updated.fileName;
        log = isInOutputDirectory(image.filePath) ? 'Output file renamed to ${updated.fileName}.' : 'File output dibuat di microstock_output: ${updated.fileName}. Original tetap aman.';
      });
      await storage.save(state.copyWith(settings: _settings()));
    } catch (e) {
      setState(() => log = 'Gagal rename file: $e');
    }
  }

  Future<void> _writeMetadataToCurrentFile() async {
    _saveEditor(markEdited: true);
    final image = current;
    if (image == null) return;
    final errors = validateMetadata(image.metadata, _settings().keywordLimit);
    if (errors.isNotEmpty) {
      setState(() => log = 'Perbaiki metadata dulu: ${errors.join(', ')}');
      return;
    }
    try {
      final outputImage = await copyImageToOutput(image);
      final result = await MetadataFileWriter.write(outputImage);
      final next = [...state.images];
      next[selected] = outputImage;
      state = state.copyWith(images: next);
      _fillEditor(outputImage);
      await storage.save(state.copyWith(settings: _settings()));
      setState(() => log = '$result File output: ${outputImage.filePath}');
    } catch (e) {
      setState(() => log = '$e');
    }
  }

  Future<void> _exportCsv() async {
    _saveEditor();
    final output = await FilePicker.platform.saveFile(
      dialogTitle: 'Export metadata CSV',
      fileName: 'microstock_metadata.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (output == null) return;
    final rows = [
      ['filename', 'title', 'description', 'keywords', 'category', 'editorial', 'commercial_use', 'ai_generated', 'status'],
      ...state.images.where((i) => i.metadata.title.isNotEmpty).map((i) => [
            i.fileName,
            i.metadata.title,
            i.metadata.description,
            i.metadata.keywords.join(', '),
            i.metadata.category,
            '${i.metadata.editorial}',
            '${i.metadata.commercialUse}',
            '${i.metadata.aiGenerated}',
            i.status,
          ]),
    ];
    await File(output).writeAsString(rows.map((r) => r.map(escapeCsv).join(',')).join('\n'));
    setState(() => log = 'CSV exported: $output');
  }

  void _deleteCurrent() {
    final image = current;
    if (image == null) return;
    final images = state.images.where((i) => i.filePath != image.filePath).toList();
    setState(() {
      state = state.copyWith(images: images);
      selected = images.isEmpty ? -1 : selected.clamp(0, images.length - 1);
      if (current != null) {
        _fillEditor(current!);
      } else {
        fileNameCtrl.clear();
        titleCtrl.clear();
        descCtrl.clear();
        keywordsCtrl.clear();
      }
      log = 'Removed ${image.fileName} from library.';
    });
    storage.save(state.copyWith(settings: _settings()));
  }

  Future<void> _clearLibrary() async {
    setState(() {
      state = state.copyWith(images: []);
      selected = -1;
      importPathCtrl.clear();
      fileNameCtrl.clear();
      titleCtrl.clear();
      descCtrl.clear();
      keywordsCtrl.clear();
      category = categories.first;
      log = 'All imported items removed from library. Files on disk were not deleted.';
    });
    await storage.save(state.copyWith(settings: _settings()));
  }

  @override
  Widget build(BuildContext context) {
    final success = state.images.where((i) => i.status == ImageStatus.success).length;
    final failed = state.images.where((i) => i.status == ImageStatus.failed).length;
    final review = state.images.where((i) => i.status == ImageStatus.review).length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Microstock Metadata AI'),
        actions: [
          TextButton.icon(onPressed: _importFiles, icon: const Icon(Icons.add_photo_alternate), label: const Text('Import')),
          TextButton.icon(onPressed: _importFolder, icon: const Icon(Icons.folder_open), label: const Text('Folder')),
          TextButton.icon(onPressed: current == null || batchRunning ? null : _generateCurrent, icon: const Icon(Icons.auto_awesome), label: const Text('Generate')),
          TextButton.icon(onPressed: batchRunning ? null : _batch, icon: const Icon(Icons.playlist_play), label: const Text('Batch')),
          TextButton.icon(onPressed: _exportCsv, icon: const Icon(Icons.file_download), label: const Text('Export CSV')),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              StatCard('Total', '${state.images.length}'),
              StatCard('Success', '$success'),
              StatCard('Failed', '$failed'),
              StatCard('Review', '$review'),
              const SizedBox(width: 16),
              if (batchRunning) ...[
                OutlinedButton.icon(onPressed: () => stopBatch = true, icon: const Icon(Icons.stop), label: const Text('Stop')),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(onPressed: batchRunning ? null : _retryFailed, icon: const Icon(Icons.refresh), label: const Text('Retry Failed')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: batchRunning ? null : _batchRenameFiles, icon: const Icon(Icons.drive_file_rename_outline), label: const Text('Batch Rename')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: batchRunning ? null : _batchWriteMetadataToFiles, icon: const Icon(Icons.edit_note), label: const Text('Batch Write')),
            ]),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 330, child: _library()),
              const SizedBox(width: 16),
              Expanded(child: _editor()),
              const SizedBox(width: 16),
              SizedBox(width: 360, child: _settingsPanel()),
            ]),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text(log, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _library() => Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.all(12), child: Text('Library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              TextField(
                controller: importPathCtrl,
                decoration: const InputDecoration(
                  labelText: 'Import path fallback',
                  hintText: '/home/user/Pictures atau /home/user/image.jpg',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _importManualPath(),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(onPressed: _importManualPath, icon: const Icon(Icons.input), label: const Text('Import Path')),
              ),
            ]),
          ),
          Expanded(
            child: state.images.isEmpty
                ? const Center(child: Text('Import JPG, PNG, atau WEBP.'))
                : ListView.builder(
                    itemCount: state.images.length,
                    itemBuilder: (context, index) {
                      final image = state.images[index];
                      return ListTile(
                        selected: index == selected,
                        leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(image.filePath), width: 48, height: 48, fit: BoxFit.cover)),
                        title: Text(image.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${image.resolutionLabel} | ${formatBytes(image.fileSize)} | ${image.status}'),
                        trailing: Text('${image.metadata.keywords.length} kw'),
                        onTap: () {
                          _saveEditor();
                          setState(() {
                            selected = index;
                            _fillEditor(image);
                          });
                        },
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: current == null ? null : _deleteCurrent, icon: const Icon(Icons.delete_outline), label: const Text('Delete selected')),
              OutlinedButton.icon(onPressed: state.images.isEmpty ? null : _clearLibrary, icon: const Icon(Icons.clear_all), label: const Text('Remove all imports')),
            ]),
          ),
        ]),
      );

  Widget _editor() {
    final image = current;
    final previewMetadata = ImageMetadata.empty().copyWith(title: titleCtrl.text, description: descCtrl.text, keywords: parseKeywords(keywordsCtrl.text), category: category);
    final validation = image == null ? <String>[] : validateMetadata(previewMetadata, _settings().keywordLimit);
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Metadata Editor', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (image == null)
            const SizedBox(height: 260, child: Center(child: Text('Pilih gambar untuk preview.')))
          else ...[
            Container(
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: Colors.black12),
              child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(File(image.filePath), fit: BoxFit.contain)),
            ),
            const SizedBox(height: 8),
            Text('${image.fileName} | ${image.resolutionLabel} | ${formatBytes(image.fileSize)}'),
          ],
          const SizedBox(height: 16),
          TextField(controller: fileNameCtrl, decoration: const InputDecoration(labelText: 'Output filename', border: OutlineInputBorder(), helperText: 'Rename membuat copy di folder microstock_output. Original tidak diubah.')),
          const SizedBox(height: 12),
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: descCtrl, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: keywordsCtrl, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Keywords, comma separated', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (value) => setState(() => category = value ?? categories.first),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(onPressed: image == null ? null : _saveMetadata, icon: const Icon(Icons.save), label: const Text('Save metadata')),
            FilledButton.tonalIcon(onPressed: image == null ? null : _renameCurrentFile, icon: const Icon(Icons.drive_file_rename_outline), label: const Text('Rename file')),
            FilledButton.tonalIcon(onPressed: image == null ? null : _writeMetadataToCurrentFile, icon: const Icon(Icons.edit_note), label: const Text('Write to file')),
            OutlinedButton.icon(onPressed: image == null || batchRunning ? null : _generateCurrent, icon: const Icon(Icons.auto_awesome), label: const Text('Regenerate')),
          ]),
          if (validation.isNotEmpty) InfoPanel('Validation', validation),
          if ((image?.metadata.warnings.isNotEmpty ?? false)) InfoPanel('Warnings', image!.metadata.warnings),
          if ((image?.metadata.rawResponse ?? '').isNotEmpty) ExpansionTile(title: const Text('Raw AI response'), children: [SelectableText(image!.metadata.rawResponse)]),
        ]),
      ),
    );
  }

  Widget _settingsPanel() => Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Settings AI API', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(controller: baseUrlCtrl, decoration: const InputDecoration(labelText: 'Base URL, contoh http://host:port/v1', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: apiKeyCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'API Key', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: timeoutCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Timeout', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: retryCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Retry', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 10),
            TextField(controller: keywordLimitCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max keywords', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(onPressed: _testApi, icon: const Icon(Icons.wifi_tethering), label: const Text('Test')),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _persist, icon: const Icon(Icons.save), label: const Text('Save')),
            ]),
            const Divider(height: 28),
            Text('Prompt Template', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(controller: promptCtrl, minLines: 12, maxLines: 18, decoration: const InputDecoration(border: OutlineInputBorder())),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => setState(() => promptCtrl.text = defaultPrompt), icon: const Icon(Icons.restore), label: const Text('Reset prompt')),
          ]),
        ),
      );
}

class AiClient {
  AiClient(this.settings);

  final AppSettings settings;

  Uri get chatUri {
    final base = settings.baseUrl.endsWith('/') ? settings.baseUrl.substring(0, settings.baseUrl.length - 1) : settings.baseUrl;
    return Uri.parse(base.endsWith('/chat/completions') ? base : '$base/chat/completions');
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (settings.apiKey.isNotEmpty) 'Authorization': 'Bearer ${settings.apiKey}',
      };

  Future<void> testConnection() async {
    final response = await http
        .post(chatUri, headers: headers, body: jsonEncode({'model': settings.model, 'messages': [{'role': 'user', 'content': 'Return JSON only: {"ok": true}'}]}))
        .timeout(Duration(seconds: settings.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) throw 'HTTP ${response.statusCode}: ${response.body}';
  }

  Future<ImageMetadata> generate(String imagePath, String fileName) async {
    final dataUrl = 'data:${mimeTypeFor(imagePath)};base64,${base64Encode(await File(imagePath).readAsBytes())}';
    Object? lastError;
    for (var attempt = 0; attempt <= settings.maxRetries; attempt++) {
      try {
        final payload = {
          'model': settings.model,
          'messages': [
            {'role': 'system', 'content': 'You are a microstock metadata assistant.'},
            {'role': 'user', 'content': [{'type': 'text', 'text': '${settings.prompt}\n\nImage filename: $fileName'}, {'type': 'image_url', 'image_url': {'url': dataUrl}}]},
          ],
        };
        final response = await http.post(chatUri, headers: headers, body: jsonEncode(payload)).timeout(Duration(seconds: settings.timeoutSeconds));
        if (response.statusCode < 200 || response.statusCode >= 300) throw 'HTTP ${response.statusCode}: ${response.body}';
        final raw = extractAssistantContent(response.body);
        return ImageMetadata.fromJson(parseJsonObject(raw)).copyWith(rawResponse: raw);
      } catch (e) {
        lastError = e;
        if (attempt < settings.maxRetries) await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    throw lastError ?? 'Unknown API error';
  }
}

class MetadataFileWriter {
  static Future<String> write(ImageItem image) async {
    final metadata = image.metadata;
    final args = <String>[
      '-overwrite_original',
      '-charset',
      'iptc=UTF8',
      '-XMP-dc:Title=${metadata.title}',
      '-XMP-dc:Description=${metadata.description}',
      '-IPTC:ObjectName=${metadata.title}',
      '-IPTC:Caption-Abstract=${metadata.description}',
      '-XMP-photoshop:Category=${metadata.category}',
      '-XMP-dc:Subject=',
      '-IPTC:Keywords=',
    ];
    for (final keyword in metadata.keywords) {
      args.add('-XMP-dc:Subject+=$keyword');
      args.add('-IPTC:Keywords+=$keyword');
    }
    args.add(image.filePath);

    ProcessResult result;
    try {
      result = await Process.run('exiftool', args);
    } on ProcessException {
      throw 'exiftool tidak ditemukan. Install exiftool agar aplikasi bisa menulis metadata langsung ke file gambar.';
    }
    final output = '${result.stdout}\n${result.stderr}'.trim();
    if (result.exitCode != 0) {
      throw 'Gagal menulis metadata ke file: $output';
    }
    return output.isEmpty ? 'Metadata berhasil ditulis ke file.' : 'Metadata berhasil ditulis ke file. $output';
  }
}

String extractAssistantContent(String body) {
  final decoded = jsonDecode(body);
  if (decoded is Map<String, dynamic>) {
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final message = choices.first['message'];
      final content = message is Map ? message['content'] : null;
      if (content is String) return content;
      if (content is List) return content.map((i) => i is Map ? i['text'] ?? '' : '$i').join('\n');
    }
    final output = decoded['output_text'];
    if (output is String) return output;
  }
  return body;
}

Map<String, dynamic> parseJsonObject(String text) {
  final cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
  try {
    final decoded = jsonDecode(cleaned);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  final start = cleaned.indexOf('{');
  final end = cleaned.lastIndexOf('}');
  if (start >= 0 && end > start) {
    final decoded = jsonDecode(cleaned.substring(start, end + 1));
    if (decoded is Map<String, dynamic>) return decoded;
  }
  throw 'Response AI bukan JSON valid.';
}

Future<(int?, int?)> readResolution(File file) async {
  try {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final result = (image.width, image.height);
    image.dispose();
    return result;
  } catch (_) {
    return (null, null);
  }
}

List<String> parseKeywords(String input) {
  final seen = <String>{};
  final result = <String>[];
  for (final part in input.split(RegExp('[,\\n]'))) {
    final keyword = part.trim().toLowerCase();
    if (keyword.isNotEmpty && seen.add(keyword)) result.add(keyword);
  }
  return result;
}

List<String> validateMetadata(ImageMetadata metadata, int maxKeywords) {
  final errors = <String>[];
  if (metadata.title.trim().isEmpty) errors.add('title kosong');
  if (metadata.description.trim().isEmpty) errors.add('description kosong');
  if (metadata.keywords.length < 5) errors.add('keyword minimal 5');
  if (metadata.keywords.length > maxKeywords) errors.add('keyword lebih dari $maxKeywords');
  if (metadata.category.trim().isEmpty) errors.add('category kosong');
  if (metadata.keywords.any((k) => k.length > 40)) errors.add('keyword terlalu panjang');
  return errors;
}

String escapeCsv(String value) {
  final escaped = value.replaceAll('"', '""');
  return escaped.contains(RegExp('[",\n]')) ? '"$escaped"' : escaped;
}

String mimeTypeFor(String path) => switch (p.extension(path).toLowerCase()) {'.png' => 'image/png', '.webp' => 'image/webp', _ => 'image/jpeg'};

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String slugFileName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '')
      .trim();
}

Future<String> uniqueFilePath(String directory, String baseName, String extension, String currentPath) async {
  var candidate = p.join(directory, '$baseName$extension');
  if (candidate == currentPath || !await File(candidate).exists()) return candidate;
  var index = 2;
  while (true) {
    candidate = p.join(directory, '$baseName-$index$extension');
    if (candidate != currentPath && !await File(candidate).exists()) return candidate;
    index++;
  }
}

bool isInOutputDirectory(String filePath) => p.basename(p.dirname(filePath)) == 'microstock_output';

Future<Directory> outputDirectoryFor(String filePath) async {
  final directory = isInOutputDirectory(filePath) ? Directory(p.dirname(filePath)) : Directory(p.join(p.dirname(filePath), 'microstock_output'));
  await directory.create(recursive: true);
  return directory;
}

Future<File> moveOrCopyToOutput(String sourcePath, String targetPath) async {
  if (sourcePath == targetPath) return File(sourcePath);
  if (isInOutputDirectory(sourcePath)) {
    return File(sourcePath).rename(targetPath);
  }
  return File(sourcePath).copy(targetPath);
}

Future<ImageItem> copyImageToOutput(ImageItem image) async {
  if (isInOutputDirectory(image.filePath)) return image;
  final outputDir = await outputDirectoryFor(image.filePath);
  final targetPath = await uniqueFilePath(
    outputDir.path,
    p.basenameWithoutExtension(image.fileName),
    p.extension(image.fileName),
    image.filePath,
  );
  final copied = await File(image.filePath).copy(targetPath);
  return image.copyWith(
    filePath: copied.path,
    fileName: p.basename(copied.path),
    fileSize: await copied.length(),
    updatedAt: DateTime.now(),
  );
}

class LocalStorage {
  Future<File> get file async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File(p.join(dir.path, 'microstock_metadata_state.json'));
  }

  Future<AppState> load() async {
    try {
      final stateFile = await file;
      if (!await stateFile.exists()) return AppState.empty();
      final decoded = jsonDecode(await stateFile.readAsString());
      if (decoded is Map<String, dynamic>) return AppState.fromJson(decoded);
    } catch (_) {}
    return AppState.empty();
  }

  Future<void> save(AppState state) async => (await file).writeAsString(const JsonEncoder.withIndent('  ').convert(state.toJson()));
}

class AppState {
  AppState({required this.images, required this.settings});
  final List<ImageItem> images;
  final AppSettings settings;
  factory AppState.empty() => AppState(images: [], settings: AppSettings.defaults());
  factory AppState.fromJson(Map<String, dynamic> json) => AppState(
        images: (json['images'] as List? ?? []).whereType<Map>().map((i) => ImageItem.fromJson(Map<String, dynamic>.from(i))).toList(),
        settings: AppSettings.fromJson(Map<String, dynamic>.from(json['settings'] as Map? ?? {})),
      );
  AppState copyWith({List<ImageItem>? images, AppSettings? settings}) => AppState(images: images ?? this.images, settings: settings ?? this.settings);
  Map<String, dynamic> toJson() => {'images': images.map((i) => i.toJson()).toList(), 'settings': settings.toJson()};
}

class AppSettings {
  AppSettings({required this.baseUrl, required this.apiKey, required this.model, required this.timeoutSeconds, required this.maxRetries, required this.keywordLimit, required this.prompt});
  final String baseUrl;
  final String apiKey;
  final String model;
  final int timeoutSeconds;
  final int maxRetries;
  final int keywordLimit;
  final String prompt;
  factory AppSettings.defaults() => AppSettings(baseUrl: '', apiKey: '', model: 'gpt-5.5', timeoutSeconds: 120, maxRetries: 2, keywordLimit: 50, prompt: defaultPrompt);
  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? 'gpt-5.5',
        timeoutSeconds: json['timeoutSeconds'] as int? ?? 120,
        maxRetries: json['maxRetries'] as int? ?? 2,
        keywordLimit: json['keywordLimit'] as int? ?? 50,
        prompt: json['prompt'] as String? ?? defaultPrompt,
      );
  Map<String, dynamic> toJson() => {'baseUrl': baseUrl, 'apiKey': apiKey, 'model': model, 'timeoutSeconds': timeoutSeconds, 'maxRetries': maxRetries, 'keywordLimit': keywordLimit, 'prompt': prompt};
}

class ImageStatus {
  static const pending = 'Belum diproses';
  static const processing = 'Sedang diproses';
  static const success = 'Berhasil';
  static const failed = 'Gagal';
  static const review = 'Perlu review';
  static const edited = 'Sudah diedit manual';
}

class ImageItem {
  ImageItem({required this.filePath, required this.fileName, required this.width, required this.height, required this.fileSize, required this.status, required this.metadata, required this.updatedAt});
  final String filePath;
  final String fileName;
  final int? width;
  final int? height;
  final int fileSize;
  final String status;
  final ImageMetadata metadata;
  final DateTime updatedAt;
  String get resolutionLabel => width == null || height == null ? 'unknown' : '${width}x$height';
  factory ImageItem.fromJson(Map<String, dynamic> json) => ImageItem(
        filePath: json['filePath'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        width: json['width'] as int?,
        height: json['height'] as int?,
        fileSize: json['fileSize'] as int? ?? 0,
        status: json['status'] as String? ?? ImageStatus.pending,
        metadata: ImageMetadata.fromJson(Map<String, dynamic>.from(json['metadata'] as Map? ?? {})),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
  ImageItem copyWith({String? filePath, String? fileName, int? fileSize, String? status, ImageMetadata? metadata, DateTime? updatedAt}) => ImageItem(filePath: filePath ?? this.filePath, fileName: fileName ?? this.fileName, width: width, height: height, fileSize: fileSize ?? this.fileSize, status: status ?? this.status, metadata: metadata ?? this.metadata, updatedAt: updatedAt ?? this.updatedAt);
  Map<String, dynamic> toJson() => {'filePath': filePath, 'fileName': fileName, 'width': width, 'height': height, 'fileSize': fileSize, 'status': status, 'metadata': metadata.toJson(), 'updatedAt': updatedAt.toIso8601String()};
}

class ImageMetadata {
  ImageMetadata({required this.title, required this.description, required this.keywords, required this.category, required this.editorial, required this.commercialUse, required this.aiGenerated, required this.warnings, required this.rawResponse});
  final String title;
  final String description;
  final List<String> keywords;
  final String category;
  final bool editorial;
  final bool commercialUse;
  final bool aiGenerated;
  final List<String> warnings;
  final String rawResponse;
  factory ImageMetadata.empty() => ImageMetadata(title: '', description: '', keywords: [], category: categories.first, editorial: false, commercialUse: true, aiGenerated: false, warnings: [], rawResponse: '');
  factory ImageMetadata.fromJson(Map<String, dynamic> json) => ImageMetadata(
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        keywords: (json['keywords'] as List? ?? []).map((i) => '$i'.trim().toLowerCase()).where((i) => i.isNotEmpty).toSet().toList(),
        category: json['category'] as String? ?? categories.first,
        editorial: json['editorial'] as bool? ?? false,
        commercialUse: json['commercial_use'] as bool? ?? json['commercialUse'] as bool? ?? true,
        aiGenerated: json['ai_generated'] as bool? ?? json['aiGenerated'] as bool? ?? false,
        warnings: (json['warnings'] as List? ?? []).map((i) => '$i').toList(),
        rawResponse: json['rawResponse'] as String? ?? '',
      );
  ImageMetadata copyWith({String? title, String? description, List<String>? keywords, String? category, bool? editorial, bool? commercialUse, bool? aiGenerated, List<String>? warnings, String? rawResponse}) => ImageMetadata(title: title ?? this.title, description: description ?? this.description, keywords: keywords ?? this.keywords, category: category ?? this.category, editorial: editorial ?? this.editorial, commercialUse: commercialUse ?? this.commercialUse, aiGenerated: aiGenerated ?? this.aiGenerated, warnings: warnings ?? this.warnings, rawResponse: rawResponse ?? this.rawResponse);
  Map<String, dynamic> toJson() => {'title': title, 'description': description, 'keywords': keywords, 'category': category, 'editorial': editorial, 'commercial_use': commercialUse, 'ai_generated': aiGenerated, 'warnings': warnings, 'rawResponse': rawResponse};
}

class StatCard extends StatelessWidget {
  const StatCard(this.label, this.value, {super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), child: Column(children: [Text(value, style: Theme.of(context).textTheme.titleLarge), Text(label)])));
}

class InfoPanel extends StatelessWidget {
  const InfoPanel(this.title, this.items, {super.key});
  final String title;
  final List<String> items;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 6), for (final item in items) Text('- $item')]),
      );
}
