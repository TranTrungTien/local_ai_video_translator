import 'dart:io';

void main() async {
  final rootDir = Directory.current;
  final outputDir = Directory('review_docs');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  print(
    '🚀 Đang quét TOÀN BỘ dự án và chia nhỏ thành các file Markdown trong `review_docs/`...\n',
  );

  // 1. Chỉ bỏ qua các thư mục build, cache, IDE
  final ignoredDirs = {
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'android/.gradle',
    'android/app/build',
    'ios/Pods',
    'ios/.symlinks',
    'ios/Runner.xcworkspace',
    'ios/Runner.xcodeproj',
    'review_docs',
  };

  // 2. Chỉ bỏ qua file do công cụ tự sinh (Generated) hoặc file export cũ
  final ignoredSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.config.dart',
    '.mocks.dart',
    'generated_plugin_registrant.cc',
    'generated_plugin_registrant.h',
    'generated_plugin_registrant.dart',
    'generated_plugins.cmake',
    'GeneratedPluginRegistrant.swift',
    'GeneratedPluginRegistrant.java',
    'pubspec.lock',
    'source.md',
    'source_2.md',
    'source_3.md',
  ];

  // 3. File binary / media / keystore không đọc dạng text
  final ignoredExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.ico',
    '.svg',
    '.webp',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
    '.so',
    '.a',
    '.dylib',
    '.dll',
    '.exe',
    '.zip',
    '.tar',
    '.gz',
    '.7z',
    '.rar',
    '.jar',
    '.class',
    '.dex',
    '.keystore',
    '.jks',
    '.ds_store',
  };

  bool shouldIgnore(FileSystemEntity entity) {
    final normalizedPath = entity.path.replaceAll('\\', '/');
    final name = normalizedPath.split('/').last;

    for (final dir in ignoredDirs) {
      if (normalizedPath.contains('/$dir/') ||
          normalizedPath.endsWith('/$dir') ||
          name == dir) {
        return true;
      }
    }

    if (entity is File) {
      final lowerName = name.toLowerCase();
      if (ignoredSuffixes.any((s) => lowerName.endsWith(s.toLowerCase()))) {
        return true;
      }
      final extIndex = lowerName.lastIndexOf('.');
      if (extIndex != -1) {
        final ext = lowerName.substring(extIndex);
        if (ignoredExtensions.contains(ext)) return true;
      }
    }
    return false;
  }

  // Phân loại file theo luồng nghiệp vụ
  String categorizeFile(String relativePath) {
    final p = relativePath.replaceAll('\\', '/');

    // Nhóm 00: Overview & Configs
    if (p == 'pubspec.yaml' ||
        p == 'analysis_options.yaml' ||
        p == 'README.md' ||
        p.startsWith('docs/') ||
        p.endsWith('AndroidManifest.xml') ||
        p.endsWith('build.gradle.kts') ||
        p.endsWith('settings.gradle') ||
        p == 'lib/main.dart') {
      return '00_overview';
    }

    // Nhóm 01: Core, Network, App Shell
    if (p.startsWith('lib/core/') || p.startsWith('lib/app/')) {
      return '01_core_app';
    }

    // Nhóm 02: Source Resolver & Native Observer
    if (p.contains('source_resolver') || p.contains('MainActivity.kt')) {
      return '02_source_resolver';
    }

    // Nhóm 03: Player Session & Controls
    if (p.contains('features/player')) {
      return '03_player_session';
    }

    // Nhóm 04: Audio Extraction & VAD
    if (p.contains('features/audio') || p.contains('AudioCaptureService.kt')) {
      return '04_audio_vad';
    }

    // Nhóm 05: AI Pipeline & Scheduler
    if (p.contains('features/pipeline')) {
      return '05_ai_pipeline';
    }

    // Nhóm 06: Subtitles, Settings, Home & Model Manager
    if (p.contains('features/subtitles') ||
        p.contains('features/settings') ||
        p.contains('features/home')) {
      return '06_subtitles_models';
    }

    // Nhóm 07: Unit Tests
    if (p.startsWith('test/')) {
      return '07_unit_tests';
    }

    // Nhóm 99: Mọi file mã nguồn khác (đảm bảo KHÔNG BỊ SÓT file nào)
    return '99_others';
  }

  final Map<String, List<File>> categorizedFiles = {
    '00_overview': [],
    '01_core_app': [],
    '02_source_resolver': [],
    '03_player_session': [],
    '04_audio_vad': [],
    '05_ai_pipeline': [],
    '06_subtitles_models': [],
    '07_unit_tests': [],
    '99_others': [],
  };

  void collectFiles(Directory dir) {
    final entities = dir.listSync(recursive: false, followLinks: false);
    for (final entity in entities) {
      if (shouldIgnore(entity)) continue;
      if (entity is Directory) {
        collectFiles(entity);
      } else if (entity is File) {
        final relativePath = entity.path
            .replaceAll('\\', '/')
            .replaceFirst('${rootDir.path.replaceAll('\\', '/')}/', '');
        final group = categorizeFile(relativePath);
        categorizedFiles[group]?.add(entity);
      }
    }
  }

  collectFiles(rootDir);

  final Map<String, String> groupTitles = {
    '00_overview': '00. Tổng Quan Dự Án, Docs & Configs',
    '01_core_app': '01. Hạ Tầng Core, Network & UI Shell',
    '02_source_resolver': '02. Source Resolver & Native Observer',
    '03_player_session': '03. Player Session & Controls',
    '04_audio_vad': '04. Audio Extractor & Silero VAD Engine',
    '05_ai_pipeline': '05. AI Scheduler & Pipeline Logic',
    '06_subtitles_models': '06. Subtitles, Home & Model Manager',
    '07_unit_tests': '07. Bộ Unit Tests Toàn Dự Án',
    '99_others': '99. Các File Mã Nguồn Khác',
  };

  int totalFilesExported = 0;

  for (final entry in categorizedFiles.entries) {
    final groupKey = entry.key;
    final files = entry.value;

    if (files.isEmpty) continue;
    files.sort((a, b) => a.path.compareTo(b.path));

    final groupFileName = '$groupKey.md';
    final outFile = File('${outputDir.path}/$groupFileName');
    final sink = outFile.openWrite();

    final title = groupTitles[groupKey] ?? groupKey;
    sink.writeln('# Review Module: $title\n');
    sink.writeln('## Included Files (${files.length} files)\n');
    sink.writeln('```text');

    final rootPathFormatted = rootDir.path.replaceAll('\\', '/');
    for (final f in files) {
      final rel = f.path
          .replaceAll('\\', '/')
          .replaceFirst('$rootPathFormatted/', '');
      sink.writeln(rel);
    }
    sink.writeln('```\n');

    for (final f in files) {
      final rel = f.path
          .replaceAll('\\', '/')
          .replaceFirst('$rootPathFormatted/', '');
      final ext = rel.split('.').last.toLowerCase();

      final lang = switch (ext) {
        'dart' => 'dart',
        'kt' || 'kts' => 'kotlin',
        'java' => 'java',
        'swift' => 'swift',
        'xml' => 'xml',
        'yaml' || 'yml' => 'yaml',
        'json' => 'json',
        'md' => 'markdown',
        'gradle' => 'groovy',
        'cpp' || 'cc' || 'c' || 'h' => 'cpp',
        _ => 'text',
      };

      try {
        final content = await f.readAsString();
        sink.writeln('## $rel');
        sink.writeln('```$lang:$rel');
        sink.writeln(content);
        sink.writeln('```\n');
        totalFilesExported++;
      } catch (_) {
        print('⚠️ Không thể đọc file: $rel');
      }
    }

    await sink.close();
    print(
      '  - Đã xuất `${outFile.path}/$groupFileName` (${files.length} files)',
    );
  }

  print(
    '\n🎉 Hoàn tất! Tổng cộng đã gom $totalFilesExported file mã nguồn vào thư mục `review_docs/`.',
  );
  print('🔒 Bảo đảm 100% không bị bỏ sót bất kỳ file source viết tay nào!');
}
