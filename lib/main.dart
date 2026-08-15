import 'dart:async';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'ad_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  unawaited(MobileAds.instance.initialize());
  await AppAnalytics.initialize();
  runApp(const InventoryCounterApp());
}

class InventoryCounterApp extends StatelessWidget {
  const InventoryCounterApp({super.key, this.showAds = true});

  final bool showAds;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '재고 실사 바코드 카운터',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff0f766e),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f2),
        useMaterial3: true,
      ),
      home: HomeScreen(showAds: showAds),
    );
  }
}

class InventorySession {
  const InventorySession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.itemCount = 0,
    this.totalQuantity = 0,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int itemCount;
  final int totalQuantity;

  InventorySession copyWith({
    String? title,
    DateTime? updatedAt,
    int? itemCount,
    int? totalQuantity,
  }) {
    return InventorySession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      itemCount: itemCount ?? this.itemCount,
      totalQuantity: totalQuantity ?? this.totalQuantity,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static InventorySession fromMap(Map<String, Object?> map) {
    return InventorySession(
      id: map['id'] as String,
      title: map['title'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      itemCount: (map['item_count'] as int?) ?? 0,
      totalQuantity: (map['total_quantity'] as int?) ?? 0,
    );
  }
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.sessionId,
    required this.code,
    required this.quantity,
    required this.firstScannedAt,
    required this.lastScannedAt,
    this.name,
  });

  final String id;
  final String sessionId;
  final String code;
  final String? name;
  final int quantity;
  final DateTime firstScannedAt;
  final DateTime lastScannedAt;

  InventoryItem copyWith({
    String? name,
    int? quantity,
    DateTime? lastScannedAt,
  }) {
    return InventoryItem(
      id: id,
      sessionId: sessionId,
      code: code,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      firstScannedAt: firstScannedAt,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'code': code,
      'name': name,
      'quantity': quantity,
      'first_scanned_at': firstScannedAt.toIso8601String(),
      'last_scanned_at': lastScannedAt.toIso8601String(),
    };
  }

  static InventoryItem fromMap(Map<String, Object?> map) {
    return InventoryItem(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      code: map['code'] as String,
      name: map['name'] as String?,
      quantity: map['quantity'] as int,
      firstScannedAt: DateTime.parse(map['first_scanned_at'] as String),
      lastScannedAt: DateTime.parse(map['last_scanned_at'] as String),
    );
  }
}

class ScanAction {
  const ScanAction({required this.code, required this.wasNew});

  final String code;
  final bool wasNew;
}

class InventoryRepository {
  InventoryRepository._();

  static final instance = InventoryRepository._();
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final dbPath = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dbPath, 'inventory_barcode_counter.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE items(
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            code TEXT NOT NULL,
            name TEXT,
            quantity INTEGER NOT NULL,
            first_scanned_at TEXT NOT NULL,
            last_scanned_at TEXT NOT NULL,
            UNIQUE(session_id, code),
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
      },
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    );
    _database = db;
    return db;
  }

  Future<List<InventorySession>> fetchSessions() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT s.*,
        COUNT(i.id) AS item_count,
        COALESCE(SUM(i.quantity), 0) AS total_quantity
      FROM sessions s
      LEFT JOIN items i ON i.session_id = s.id
      GROUP BY s.id
      ORDER BY s.updated_at DESC
    ''');
    return rows.map(InventorySession.fromMap).toList();
  }

  Future<InventorySession> createSession() async {
    final now = DateTime.now();
    final title = '실사 ${DateFormat('yyyy-MM-dd HH:mm').format(now)}';
    final session = InventorySession(
      id: now.microsecondsSinceEpoch.toString(),
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    final db = await database;
    await db.insert('sessions', session.toMap());
    await AppAnalytics.log('session_create');
    return session;
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    await AppAnalytics.log('session_delete');
  }

  Future<List<InventoryItem>> fetchItems(
    String sessionId, {
    ItemSort sort = ItemSort.recent,
    String query = '',
  }) async {
    final db = await database;
    final normalized = query.trim();
    final where = normalized.isEmpty
        ? 'session_id = ?'
        : 'session_id = ? AND (code LIKE ? OR COALESCE(name, "") LIKE ?)';
    final whereArgs = normalized.isEmpty
        ? <Object?>[sessionId]
        : <Object?>[sessionId, '%$normalized%', '%$normalized%'];
    final orderBy = switch (sort) {
      ItemSort.recent => 'last_scanned_at DESC',
      ItemSort.code => 'code COLLATE NOCASE ASC',
      ItemSort.quantity => 'quantity DESC, last_scanned_at DESC',
    };
    final rows = await db.query(
      'items',
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<InventoryItem?> findItem(String sessionId, String code) async {
    final db = await database;
    final rows = await db.query(
      'items',
      where: 'session_id = ? AND code = ?',
      whereArgs: [sessionId, code],
      limit: 1,
    );
    return rows.isEmpty ? null : InventoryItem.fromMap(rows.first);
  }

  Future<ScanAction> addScan(String sessionId, String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      throw ArgumentError('Code cannot be empty');
    }
    final now = DateTime.now();
    final db = await database;
    final existing = await findItem(sessionId, code);
    if (existing == null) {
      final item = InventoryItem(
        id: now.microsecondsSinceEpoch.toString(),
        sessionId: sessionId,
        code: code,
        quantity: 1,
        firstScannedAt: now,
        lastScannedAt: now,
      );
      await db.insert('items', item.toMap());
      await _touchSession(sessionId, now);
      await AppAnalytics.log('scan_success');
      return ScanAction(code: code, wasNew: true);
    }
    await db.update(
      'items',
      {
        'quantity': existing.quantity + 1,
        'last_scanned_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    await _touchSession(sessionId, now);
    await AppAnalytics.log('scan_duplicate_merge');
    return ScanAction(code: code, wasNew: false);
  }

  Future<void> undoScan(String sessionId, String code) async {
    final existing = await findItem(sessionId, code);
    if (existing == null) return;
    final db = await database;
    if (existing.quantity <= 1) {
      await db.delete('items', where: 'id = ?', whereArgs: [existing.id]);
    } else {
      await db.update(
        'items',
        {
          'quantity': existing.quantity - 1,
          'last_scanned_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [existing.id],
      );
    }
    await _touchSession(sessionId, DateTime.now());
  }

  Future<void> updateItem(InventoryItem item) async {
    final db = await database;
    await db.update(
      'items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    await _touchSession(item.sessionId, DateTime.now());
    await AppAnalytics.log('quantity_edit');
  }

  Future<void> deleteItem(InventoryItem item) async {
    final db = await database;
    await db.delete('items', where: 'id = ?', whereArgs: [item.id]);
    await _touchSession(item.sessionId, DateTime.now());
  }

  Future<void> _touchSession(String sessionId, DateTime now) async {
    final db = await database;
    await db.update(
      'sessions',
      {'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}

class AppAnalytics {
  static FirebaseAnalytics? _analytics;

  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
    } catch (_) {
      _analytics = null;
    }
  }

  static Future<void> log(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    try {
      await _analytics?.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Analytics must not block a local-first inventory count.
    }
  }
}

enum ItemSort { recent, code, quantity }

extension ItemSortLabel on ItemSort {
  String get label {
    return switch (this) {
      ItemSort.recent => '최근순',
      ItemSort.code => '코드순',
      ItemSort.quantity => '수량순',
    };
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.showAds});

  final bool showAds;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repository = InventoryRepository.instance;
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  BannerAd? _bannerAd;
  bool _bannerLoaded = false;
  bool _loading = true;
  List<InventorySession> _sessions = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
    if (widget.showAds) _loadBannerAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final sessions = await _repository.fetchSessions();
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  void _loadBannerAd() {
    final ad = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _bannerLoaded = false);
        },
      ),
    );
    _bannerAd = ad;
    ad.load();
  }

  Future<void> _createSession() async {
    final session = await _repository.createSession();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SessionScreen(session: session, showAds: widget.showAds),
      ),
    );
    await _loadSessions();
  }

  Future<void> _openSession(InventorySession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            SessionScreen(session: session, showAds: widget.showAds),
      ),
    );
    await _loadSessions();
  }

  Future<void> _deleteSession(InventorySession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('세션 삭제'),
        content: Text('${session.title} 세션과 항목을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteSession(session.id);
    await _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('재고 실사 바코드 카운터')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadSessions,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    FilledButton.icon(
                      onPressed: _createSession,
                      icon: const Icon(Icons.add_task),
                      label: const Text('새 실사 시작'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '최근 세션',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_sessions.isEmpty)
                      const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: '저장된 실사 세션이 없습니다',
                        message: '바로 새 실사를 시작할 수 있습니다.',
                      )
                    else
                      ..._sessions.map(
                        (session) => SessionTile(
                          session: session,
                          dateFormat: _dateFormat,
                          onTap: () => _openSession(session),
                          onDelete: () => _deleteSession(session),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.showAds && _bannerLoaded && _bannerAd != null)
              SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.session,
    required this.dateFormat,
    required this.onTap,
    required this.onDelete,
  });

  final InventorySession session;
  final DateFormat dateFormat;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: onTap,
        title: Text(
          session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${session.itemCount}개 항목 · 총 ${session.totalQuantity}개 · ${dateFormat.format(session.updatedAt)}',
        ),
        trailing: IconButton(
          tooltip: '삭제',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.session,
    required this.showAds,
  });

  final InventorySession session;
  final bool showAds;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _repository = InventoryRepository.instance;
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.codabar,
      BarcodeFormat.itf14,
      BarcodeFormat.dataMatrix,
      BarcodeFormat.pdf417,
    ],
  );
  final _codeController = TextEditingController();
  BannerAd? _listBannerAd;
  InterstitialAd? _interstitialAd;
  bool _bannerLoaded = false;
  bool _busy = false;
  bool _sound = true;
  bool _vibration = true;
  String? _lastCode;
  DateTime? _lastDetectedAt;
  List<ScanAction> _scanHistory = [];
  List<InventoryItem> _items = [];
  ItemSort _sort = ItemSort.recent;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadItems();
    if (widget.showAds) {
      _loadListBannerAd();
      _loadInterstitialAd();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    _codeController.dispose();
    _listBannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  int get _totalQuantity =>
      _items.fold(0, (previous, item) => previous + item.quantity);

  Future<void> _loadItems() async {
    final items = await _repository.fetchItems(
      widget.session.id,
      sort: _sort,
      query: _query,
    );
    if (!mounted) return;
    setState(() => _items = items);
  }

  void _loadListBannerAd() {
    final ad = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _bannerLoaded = false);
        },
      ),
    );
    _listBannerAd = ad;
    ad.load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(nonPersonalizedAds: true),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  Future<void> _handleDetected(BarcodeCapture capture) async {
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (code == null) return;
    final now = DateTime.now();
    if (_lastCode == code &&
        _lastDetectedAt != null &&
        now.difference(_lastDetectedAt!) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastDetectedAt = now;
    await _addCode(code, source: ScanSource.camera);
  }

  Future<void> _addCode(String code, {required ScanSource source}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final action = await _repository.addScan(widget.session.id, code);
      if (_vibration) unawaited(HapticFeedback.mediumImpact());
      if (_sound) unawaited(SystemSound.play(SystemSoundType.click));
      await _loadItems();
      if (!mounted) return;
      setState(() {
        _lastCode = action.code;
        _scanHistory = [action, ..._scanHistory].take(20).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action.wasNew ? '새 코드 추가: ${action.code}' : '수량 +1: ${action.code}',
          ),
          duration: const Duration(milliseconds: 900),
        ),
      );
      if (source == ScanSource.manual) {
        await AppAnalytics.log('manual_code_add');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manualAdd() async {
    _codeController.clear();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('수동 코드 입력'),
        content: TextField(
          controller: _codeController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '바코드 또는 QR 코드',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _codeController.text),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    final code = value?.trim();
    if (code == null || code.isEmpty) return;
    await _addCode(code, source: ScanSource.manual);
  }

  Future<void> _undoLastScan() async {
    if (_scanHistory.isEmpty) return;
    final last = _scanHistory.first;
    await _repository.undoScan(widget.session.id, last.code);
    await _loadItems();
    if (!mounted) return;
    setState(() {
      _scanHistory = _scanHistory.skip(1).toList();
      _lastCode = _scanHistory.firstOrNull?.code;
    });
  }

  Future<void> _updateQuantity(InventoryItem item, int quantity) async {
    if (quantity <= 0) {
      await _repository.deleteItem(item);
    } else {
      await _repository.updateItem(item.copyWith(quantity: quantity));
    }
    await _loadItems();
  }

  Future<void> _editItem(InventoryItem item) async {
    final nameController = TextEditingController(text: item.name ?? '');
    final quantityController = TextEditingController(text: '${item.quantity}');
    final result = await showDialog<InventoryItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.code, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '상품명/메모',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '수량',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final quantity = int.tryParse(quantityController.text.trim());
              if (quantity == null || quantity < 0) return;
              Navigator.pop(
                context,
                item.copyWith(
                  name: nameController.text.trim().isEmpty
                      ? null
                      : nameController.text.trim(),
                  quantity: quantity,
                  lastScannedAt: DateTime.now(),
                ),
              );
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    nameController.dispose();
    quantityController.dispose();
    if (result == null) return;
    if (result.quantity <= 0) {
      await _repository.deleteItem(item);
    } else {
      await _repository.updateItem(result);
    }
    await _loadItems();
  }

  Future<File> _buildCsvFile() async {
    await AppAnalytics.log('csv_export_tap');
    final allItems = await _repository.fetchItems(widget.session.id);
    final rows = [
      ['code', 'name', 'quantity', 'first_scanned_at', 'last_scanned_at'],
      ...allItems.map(
        (item) => [
          item.code,
          item.name ?? '',
          item.quantity,
          _csvDate(item.firstScannedAt),
          _csvDate(item.lastScannedAt),
        ],
      ),
    ];
    final csvText = csv.encode(rows);
    final directory = await getApplicationDocumentsDirectory();
    final safeTitle = widget.session.title.replaceAll(
      RegExp(r'[^0-9A-Za-z가-힣_-]+'),
      '_',
    );
    final file = File(p.join(directory.path, '$safeTitle.csv'));
    await file.writeAsString(csvText);
    await AppAnalytics.log('csv_export_success', {
      'row_count': allItems.length,
    });
    return file;
  }

  Future<void> _openExport() async {
    final allItems = await _repository.fetchItems(widget.session.id);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          session: widget.session,
          items: allItems,
          onCreateFile: _buildCsvFile,
          onCompleted: _showCompletionAd,
        ),
      ),
    );
  }

  Future<void> _showCompletionAd() async {
    final ad = _interstitialAd;
    if (widget.showAds && ad != null) {
      _interstitialAd = null;
      await ad.show();
      _loadInterstitialAd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.title),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: '스캔'),
            Tab(icon: Icon(Icons.list_alt), text: '목록'),
            Tab(icon: Icon(Icons.ios_share), text: 'CSV'),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            ScanTab(
              scannerController: _scannerController,
              lastCode: _lastCode,
              itemCount: _items.length,
              totalQuantity: _totalQuantity,
              sound: _sound,
              vibration: _vibration,
              canUndo: _scanHistory.isNotEmpty,
              onDetected: _handleDetected,
              onManualAdd: _manualAdd,
              onUndo: _undoLastScan,
              onExport: _openExport,
              onSoundChanged: (value) => setState(() => _sound = value),
              onVibrationChanged: (value) => setState(() => _vibration = value),
            ),
            ItemsTab(
              items: _items,
              sort: _sort,
              query: _query,
              showAds: widget.showAds,
              bannerLoaded: _bannerLoaded,
              bannerAd: _listBannerAd,
              onSearchChanged: (value) async {
                setState(() => _query = value);
                await _loadItems();
              },
              onSortChanged: (sort) async {
                setState(() => _sort = sort);
                await _loadItems();
              },
              onEdit: _editItem,
              onIncrement: (item) => _updateQuantity(item, item.quantity + 1),
              onDecrement: (item) => _updateQuantity(item, item.quantity - 1),
              onDelete: (item) async {
                await _repository.deleteItem(item);
                await _loadItems();
              },
            ),
            ExportSummaryTab(items: _items, onExport: _openExport),
          ],
        ),
      ),
    );
  }
}

enum ScanSource { camera, manual }

String _csvDate(DateTime date) =>
    DateFormat('yyyy-MM-dd HH:mm:ss').format(date);

class ScanTab extends StatelessWidget {
  const ScanTab({
    super.key,
    required this.scannerController,
    required this.lastCode,
    required this.itemCount,
    required this.totalQuantity,
    required this.sound,
    required this.vibration,
    required this.canUndo,
    required this.onDetected,
    required this.onManualAdd,
    required this.onUndo,
    required this.onExport,
    required this.onSoundChanged,
    required this.onVibrationChanged,
  });

  final MobileScannerController scannerController;
  final String? lastCode;
  final int itemCount;
  final int totalQuantity;
  final bool sound;
  final bool vibration;
  final bool canUndo;
  final void Function(BarcodeCapture capture) onDetected;
  final VoidCallback onManualAdd;
  final VoidCallback onUndo;
  final VoidCallback onExport;
  final ValueChanged<bool> onSoundChanged;
  final ValueChanged<bool> onVibrationChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: onDetected,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                  ),
                ),
                const Center(
                  child: SizedBox(
                    width: 220,
                    height: 140,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MetricTile(label: '항목', value: '$itemCount'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: MetricTile(label: '총 수량', value: '$totalQuantity'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ListTile(
          tileColor: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Text('최근 스캔'),
          subtitle: Text(lastCode ?? '아직 스캔된 코드가 없습니다'),
          leading: const Icon(Icons.barcode_reader),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: onManualAdd,
              icon: const Icon(Icons.keyboard_alt_outlined),
              label: const Text('수동 입력'),
            ),
            OutlinedButton.icon(
              onPressed: canUndo ? onUndo : null,
              icon: const Icon(Icons.undo),
              label: const Text('최근 취소'),
            ),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.ios_share),
              label: const Text('CSV 내보내기'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          value: vibration,
          onChanged: onVibrationChanged,
          title: const Text('진동 피드백'),
          secondary: const Icon(Icons.vibration),
        ),
        SwitchListTile(
          value: sound,
          onChanged: onSoundChanged,
          title: const Text('소리 피드백'),
          secondary: const Icon(Icons.volume_up_outlined),
        ),
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      ),
    );
  }
}

class ItemsTab extends StatelessWidget {
  const ItemsTab({
    super.key,
    required this.items,
    required this.sort,
    required this.query,
    required this.showAds,
    required this.bannerLoaded,
    required this.bannerAd,
    required this.onSearchChanged,
    required this.onSortChanged,
    required this.onEdit,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  final List<InventoryItem> items;
  final ItemSort sort;
  final String query;
  final bool showAds;
  final bool bannerLoaded;
  final BannerAd? bannerAd;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<ItemSort> onSortChanged;
  final ValueChanged<InventoryItem> onEdit;
  final ValueChanged<InventoryItem> onIncrement;
  final ValueChanged<InventoryItem> onDecrement;
  final ValueChanged<InventoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: '검색',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<ItemSort>(
                tooltip: '정렬',
                initialValue: sort,
                onSelected: onSortChanged,
                itemBuilder: (context) => ItemSort.values
                    .map(
                      (value) =>
                          PopupMenuItem(value: value, child: Text(value.label)),
                    )
                    .toList(),
                icon: const Icon(Icons.sort),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const EmptyState(
                  icon: Icons.playlist_add_check,
                  title: '항목이 없습니다',
                  message: '스캔하거나 수동 입력으로 코드를 추가하세요.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return InventoryItemTile(
                      item: item,
                      onEdit: () => onEdit(item),
                      onIncrement: () => onIncrement(item),
                      onDecrement: () => onDecrement(item),
                      onDelete: () => onDelete(item),
                    );
                  },
                ),
        ),
        if (showAds && bannerLoaded && bannerAd != null)
          SizedBox(
            width: bannerAd!.size.width.toDouble(),
            height: bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: bannerAd!),
          ),
      ],
    );
  }
}

class InventoryItemTile extends StatelessWidget {
  const InventoryItemTile({
    super.key,
    required this.item,
    required this.onEdit,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
  });

  final InventoryItem item;
  final VoidCallback onEdit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onEdit,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.name?.isNotEmpty == true ? item.name! : '상품명/메모 없음',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '감소',
              onPressed: onDecrement,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '${item.quantity}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: '증가',
              onPressed: onIncrement,
              icon: const Icon(Icons.add_circle_outline),
            ),
            IconButton(
              tooltip: '삭제',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class ExportSummaryTab extends StatelessWidget {
  const ExportSummaryTab({
    super.key,
    required this.items,
    required this.onExport,
  });

  final List<InventoryItem> items;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final preview = items.take(5).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        MetricTile(label: '내보낼 행 수', value: '${items.length}'),
        const SizedBox(height: 12),
        Text('미리보기', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            [
              'code,name,quantity,first_scanned_at,last_scanned_at',
              ...preview.map(
                (item) =>
                    '${item.code},${item.name ?? ''},${item.quantity},${_csvDate(item.firstScannedAt)},${_csvDate(item.lastScannedAt)}',
              ),
            ].join('\n'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: items.isEmpty ? null : onExport,
          icon: const Icon(Icons.ios_share),
          label: const Text('CSV 저장/공유'),
        ),
      ],
    );
  }
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.session,
    required this.items,
    required this.onCreateFile,
    required this.onCompleted,
  });

  final InventorySession session;
  final List<InventoryItem> items;
  final Future<File> Function() onCreateFile;
  final Future<void> Function() onCompleted;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _busy = false;
  File? _file;

  Future<void> _saveAndShare() async {
    setState(() => _busy = true);
    try {
      final file = await widget.onCreateFile();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: widget.session.title,
          text: '${widget.session.title} CSV',
        ),
      );
      await AppAnalytics.log('share_success');
      await widget.onCompleted();
      if (!mounted) return;
      setState(() => _file = file);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV 저장 완료: ${p.basename(file.path)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.items.take(8).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('CSV 내보내기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            MetricTile(label: '내보낼 행 수', value: '${widget.items.length}'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                [
                  'code,name,quantity,first_scanned_at,last_scanned_at',
                  ...preview.map(
                    (item) =>
                        '${item.code},${item.name ?? ''},${item.quantity},${_csvDate(item.firstScannedAt)},${_csvDate(item.lastScannedAt)}',
                  ),
                ].join('\n'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || widget.items.isEmpty ? null : _saveAndShare,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: const Text('CSV 저장/공유'),
            ),
            if (_file != null) ...[
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('저장된 파일'),
                subtitle: Text(_file!.path),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
