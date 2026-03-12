import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:confetti/confetti.dart';
import 'package:uuid/uuid.dart';

// Diğer dosyaların (login_page, firebase_options, firestore_service var olduğunu varsayıyorum)
import 'login_page.dart'; 
import 'firebase_options.dart';
import 'firestore_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Not Defterim',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, 
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFe94560), // Mercan rengi
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFe94560), // Mercan rengi
          brightness: Brightness.dark,
          surface: const Color(0xFF1a1a2e), // Gece mavisi
        ),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) return const FolderPage();
          return const LoginPage();
        },
      ),
    );
  }
}

// ================= Model =================
class Item {
  String id;
  String name;
  bool isFolder;
  String? parentId;
  bool isDone;
  int priority; 
  DateTime? reminder; 
  IconData? iconData; // Klasör ikonu için
  Color? folderColor; // Klasör rengi için
  bool isArchived; // Arşiv durumu için
  List<Item> children = [];

  Item({
    required this.id,
    required this.name,
    this.isFolder = false,
    this.parentId,
    this.isDone = false,
    this.priority = 0,
    this.reminder,
    this.iconData,
    this.folderColor,
    this.isArchived = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'isFolder': isFolder ? 1 : 0,
        'parentId': parentId,
        'isDone': isDone ? 1 : 0,
        'priority': priority,
        'reminder': reminder?.toIso8601String(),
        'iconData': iconData?.codePoint, // IconData'yı codePoint olarak sakla
        'folderColor': folderColor?.value, // Color'ı value olarak sakla
        'isArchived': isArchived ? 1 : 0, // Arşiv durumunu sakla
      };

  factory Item.fromMap(Map<String, dynamic> map) => Item(
        id: map['id'],
        name: map['name'],
        isFolder: map['isFolder'] == 1 || map['isFolder'] == true,
        parentId: map['parentId'],
        isDone: map['isDone'] == 1 || map['isDone'] == true,
        priority: map['priority'] ?? 0,
        reminder: map['reminder'] != null ? DateTime.parse(map['reminder']) : null,
        iconData: map['iconData'] != null ? _getIconDataFromCodePoint(map['iconData']) : null,
        folderColor: map['folderColor'] != null ? Color(map['folderColor']) : null,
        isArchived: map['isArchived'] == 1 || map['isArchived'] == true || map['Archived'] == 1 || map['Archived'] == true,
      );
}

// IconData helper fonksiyonu
IconData? _getIconDataFromCodePoint(int? codePoint) {
  if (codePoint == null) return null;
  
  // En sık kullanılan ikonları sabitle
  switch (codePoint) {
    case 0xe2c7: return Icons.folder;
    case 0xe2c8: return Icons.folder_open;
    case 0xe838: return Icons.star;
    case 0xe8e4: return Icons.bookmark;
    case 0xe149: return Icons.archive;
    case 0xe86f: return Icons.code;
    case 0xe31a: return Icons.computer;
    case 0xe8b8: return Icons.settings;
    case 0xe227: return Icons.attach_money;
    case 0xe850: return Icons.account_balance_wallet;
    case 0xe645: return Icons.priority_high;
    default: return Icons.folder; // Varsayılan
  }
}

// ================= DB Helper =================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('todo_v4.db'); 
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    Directory dir = await getApplicationDocumentsDirectory();
    String path = p.join(dir.path, fileName);
    return await openDatabase(path, version: 3, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE items(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        isFolder INTEGER NOT NULL,
        parentId TEXT,
        isDone INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        reminder TEXT,
        iconData INTEGER,
        folderColor INTEGER,
        isArchived INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Yeni sütunları ekle
      await db.execute('ALTER TABLE items ADD COLUMN iconData INTEGER');
      await db.execute('ALTER TABLE items ADD COLUMN folderColor INTEGER');
    }
    if (oldVersion < 3) {
      try {
        // isArchived sütununu ekle (hata varsa zaten var demektir)
        await db.execute('ALTER TABLE items ADD COLUMN isArchived INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        // Eğer sütun zaten varsa hata ignore et
        print('isArchived column already exists or has typo: $e');
      }
    }
  }

  Future<int> insertItem(Item item) async {
    final db = await instance.database;
    return await db.insert('items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateItem(Item item) async {
    final db = await instance.database;
    return await db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<List<Item>> getItems({String? parentId}) async {
    final db = await instance.database;
    String whereClause;
    List<dynamic> whereArgs;
    
    try {
      whereClause = parentId == null 
          ? 'parentId IS NULL AND isArchived = 0' 
          : 'parentId = ? AND isArchived = 0';
      whereArgs = parentId == null ? [] : [parentId];
      
      final maps = await db.query('items', 
          where: whereClause, 
          whereArgs: whereArgs,
          orderBy: 'id ASC' // Her zaman aynı sıralama için
      );
      return maps.map((e) => Item.fromMap(e)).toList();
    } catch (e) {
      print('Error in getItems: $e');
      return [];
    }
  }

  Future<List<Item>> getAllItems() async {
    final db = await instance.database;
    final maps = await db.query('items');
    return maps.map((e) => Item.fromMap(e)).toList();
  }

  Future<List<Item>> getArchivedItems() async {
    final db = await instance.database;
    List<Map<String, dynamic>> maps;
    
    try {
      // Önce doğru isimle dene
      maps = await db.query('items', where: 'isArchived = ?', whereArgs: [1]);
    } catch (e) {
      // Hata olursa typo ile dene
      maps = await db.query('items', where: 'isArchicved = ?', whereArgs: [1]);
    }
    
    return maps.map((e) => Item.fromMap(e)).toList();
  }

  Future<int> deleteItem(String id) async {
    final db = await instance.database;
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }
  
  Future<void> upsertItem(Item item) async {
    final db = await instance.database;
    await db.insert('items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

// ================= Folder Page =================
class FolderPage extends StatefulWidget {
  const FolderPage({super.key});
  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  List<Item> _rootItems = [];
  late ConfettiController _createController, _doneController, _deleteController;
  StreamSubscription? _cloudSubscription;
  
  // Expansion state tracking
  final Set<String> _expandedFolders = <String>{};
  
  // Klasör ikonları listesi
  final List<IconData> _folderIcons = [
    // Genel amaçlı (5 tane)
    Icons.folder,
    Icons.folder_open,
    Icons.star,
    Icons.bookmark,
    Icons.archive,
    
    // Yazılım ile ilgili (3 tane)
    Icons.code,
    Icons.computer,
    Icons.settings,
    
    // Para ile ilgili (2 tane)
    Icons.attach_money,
    Icons.account_balance_wallet,
    
    // Çok önemli notlar için (1 tane)
    Icons.priority_high,
  ];

  // Klasör renkleri
  final List<Color> _folderColors = [
    Colors.amber,
    Colors.blue,
    Colors.green,
    Colors.red,
    Colors.purple,
  ];

  @override
  void initState() {
    super.initState();
    _createController = ConfettiController(duration: const Duration(milliseconds: 500));
    _doneController = ConfettiController(duration: const Duration(milliseconds: 800));
    _deleteController = ConfettiController(duration: const Duration(milliseconds: 400));

    _loadItems().then((_) {
      _startCloudListener(); 
    });
  }

  @override
  void dispose() {
    _createController.dispose();
    _doneController.dispose();
    _deleteController.dispose();
    _cloudSubscription?.cancel();
    super.dispose();
  }

  void _startCloudListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _cloudSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('items')
        .snapshots()
        .listen((snapshot) async {
      bool needsReload = false;
      
      for (var change in snapshot.docChanges) {
        Item item = Item.fromMap(change.doc.data()!);
        
        if (change.type == DocumentChangeType.removed) {
          await DatabaseHelper.instance.deleteItem(item.id);
          needsReload = true;
        } else {
          await DatabaseHelper.instance.upsertItem(item);
          // Arşiv durumu değişirse her zaman yeniden yükle
          if (item.isArchived == false) {
            needsReload = true;
          }
        }
      }
      
      // Gerekliyse listeyi yeniden yükle
      if (needsReload && mounted) {
        _loadItems();
      }
    });
  }

  Future<void> _loadItems() async {
    final items = await DatabaseHelper.instance.getItems(parentId: null);
    for (var item in items) {
      if (item.isFolder) item.children = await _loadChildren(item.id);
    }
    if (mounted) setState(() => _rootItems = items);
  }
  
  Future<List<Item>> _loadChildren(String parentId) async {
    final children = await DatabaseHelper.instance.getItems(parentId: parentId);
    for (var c in children) {
      if (c.isFolder) c.children = await _loadChildren(c.id);
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Not Defterim",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF1a1a2e),
                  const Color(0xFF16213e),
                  const Color(0xFF0f3460),
                ],
              ),
            ),
            child: SafeArea(
              child: DragTarget<Item>(
                onAcceptWithDetails: (details) => _moveItem(details.data, null),
                builder: (context, candidateData, rejectedData) {
                  final isHovering = candidateData.isNotEmpty;
                  
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: isHovering && _rootItems.isEmpty
                          ? Border.all(
                              color: const Color(0xFFe94560).withValues(alpha: 0.5),
                              width: 2,
                              style: BorderStyle.solid,
                            )
                          : null,
                    ),
                    child: _rootItems.isEmpty 
                      ? _buildEmptyState(isHovering)
                      : _buildItemsList(),
                  );
                },
              ),
            ),
          ),
          
          // Çöp kutusu en altta
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: DragTarget<Item>(
              onAcceptWithDetails: (details) async {
                final draggedItem = details.data;
                _deleteController.play();
                await DatabaseHelper.instance.deleteItem(draggedItem.id);
                await FirestoreService().deleteItem(draggedItem.id);
                _loadItems();
              },
              builder: (context, candidateData, _) {
                bool isHovering = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: isHovering ? 70 : 60,
                  decoration: BoxDecoration(
                    color: isHovering ? Colors.red : Colors.red.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.delete_forever, color: Colors.white, size: 28),
                  ),
                );
              },
            ),
          ),
          
          // Confetti efektleri
          Align(alignment: Alignment.topCenter, child: ConfettiWidget(confettiController: _createController, blastDirectionality: BlastDirectionality.explosive)),
          Align(alignment: Alignment.center, child: ConfettiWidget(confettiController: _doneController, blastDirectionality: BlastDirectionality.explosive)),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: "folder",
            onPressed: () => _addItem(isFolder: true),
            backgroundColor: const Color(0xFFe94560),
            child: const Icon(Icons.create_new_folder, color: Colors.white),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "note",
            onPressed: () => _addItem(isFolder: false),
            backgroundColor: const Color(0xFF16213e),
            child: const Icon(Icons.note_add, color: Colors.white),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      drawer: Drawer(
        backgroundColor: const Color(0xFF1a1a2e),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFe94560), Color(0xFF0f3460)],
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.note, color: Colors.white, size: 40),
                  SizedBox(height: 10),
                  Text(
                    'Not Defterim',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Kişisel not yöneticiniz',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home, color: Colors.white),
              title: const Text('Ana Sayfa', style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload, color: Colors.green),
              title: const Text('Veriyi Buluta Aktar', style: TextStyle(color: Colors.white)),
              onTap: () { 
                Navigator.pop(context); 
                _pushToCloud(); 
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download, color: Colors.blue),
              title: const Text('Veriyi Buluttan Çek', style: TextStyle(color: Colors.white)),
              onTap: () { 
                Navigator.pop(context); 
                _pullFromCloud(); 
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive, color: Colors.white),
              title: const Text('Arşiv', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ArchivePage()),
                );
              },
            ),
            const Divider(color: Colors.white24),
            ListTile(
              leading: const Icon(Icons.info, color: Colors.white),
              title: const Text('Hakkında', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: const Color(0xFF1a1a2e),
                    title: const Text('Not Defterim', style: TextStyle(color: Colors.white)),
                    content: const Text(
                      'Flutter ile geliştirilmiş kişisel not yönetim uygulaması.\n\nÖzellikler:\n• Not ve klasör yönetimi\n• Arşivleme\n• Drag & Drop\n• Firebase senkronizasyonu',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Kapat', style: TextStyle(color: Color(0xFFe94560))),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isHovering) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: isHovering 
              ? const Color(0xFFe94560).withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.85),
          border: isHovering 
              ? Border.all(
                  color: const Color(0xFFe94560).withValues(alpha: 0.3),
                  width: 2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                Icons.note_add_outlined,
                size: isHovering ? 100 : 80,
                color: isHovering 
                    ? const Color(0xFFe94560)
                    : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isHovering ? "Bırakın..." : "Henüz not yok",
              style: TextStyle(
                color: isHovering 
                    ? const Color(0xFFe94560)
                    : Colors.grey.shade700,
                fontSize: isHovering ? 22 : 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            if (!isHovering)
              Text(
                "Not veya klasör eklemek için butonları kullanın",
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList() {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: _rootItems.length,
      itemBuilder: (context, index) => _buildItem(_rootItems[index]),
    );
  }

  Color _getPriorityColor(int p) {
    if (p == 1) return Colors.orange.withValues(alpha: 0.9);
    if (p == 2) return Colors.redAccent.withValues(alpha: 0.9);
    return Colors.greenAccent.withValues(alpha: 0.9);
  }

  Widget _buildItem(Item item) {
    Widget content;
    if (item.isFolder) {
      content = DragTarget<Item>(
        onAcceptWithDetails: (details) => _moveItem(details.data, item.id),
        builder: (context, candidateData, rejectedData) {
          final folderColor = item.folderColor ?? Colors.amber;
          final isInitiallyExpanded = _expandedFolders.contains(item.id);
          
          return ExpansionTile(
            key: ValueKey('folder_${item.id}'),
            initiallyExpanded: isInitiallyExpanded,
            onExpansionChanged: (isExpanded) {
              if (isExpanded) {
                _expandedFolders.add(item.id);
              } else {
                _expandedFolders.remove(item.id);
              }
            },
            leading: GestureDetector(
              onTap: () => _showIconSelector(item),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: folderColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.iconData ?? Icons.folder,
                  color: folderColor,
                  size: 28,
                ),
              ),
            ),
            title: Text(
              item.name, 
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: folderColor, // Klasör rengiyle aynı
              )
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16.0),
                child: Column(children: item.children.map(_buildItem).toList()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(icon: const Icon(Icons.create_new_folder, size: 20), onPressed: () => _addItem(parentId: item.id, isFolder: true)),
                  IconButton(icon: const Icon(Icons.note_add, size: 20), onPressed: () => _addItem(parentId: item.id, isFolder: false)),
                ],
              ),
            ],
          );
        },
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
        child: Container(
          decoration: BoxDecoration(
            color: _getPriorityColor(item.priority),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: ListTile(
            leading: Checkbox(
              activeColor: Colors.black87,
              value: item.isDone,
              onChanged: (val) async {
                if (val == true) _doneController.play();
                setState(() => item.isDone = val!);
                await DatabaseHelper.instance.updateItem(item);
                await FirestoreService().syncItem(item);
                // _loadItems() çağrılmıyor - sıralama korunuyor
              },
            ),
            title: Text(item.name, style: TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w500,
              decoration: item.isDone ? TextDecoration.lineThrough : null,
            )),
            subtitle: item.reminder != null 
                ? Text("${item.reminder!.day}/${item.reminder!.month} ${item.reminder!.hour}:${item.reminder!.minute}", style: const TextStyle(color: Colors.black54)) 
                : null,
            onTap: () => _cyclePriority(item),
            trailing: IconButton(icon: const Icon(Icons.alarm, color: Colors.black54), onPressed: () => _setReminder(item)),
          ),
        ),
      );
    }

    return Dismissible(
      key: UniqueKey(), // Her seferinde benzersiz key kullan
      direction: DismissDirection.endToStart, // Sola kaydırma (sağdan sola)
      background: Container(
        color: Colors.orange,
        alignment: Alignment.centerRight,
        child: const Padding(
          padding: EdgeInsets.only(right: 20.0),
          child: Icon(Icons.archive, color: Colors.white),
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          // Arşivleme dialog'unu göster ve sonucu bekle
          final shouldArchive = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1a1a2e),
              title: const Text(
                "Arşivle",
                style: TextStyle(color: Colors.white),
              ),
              content: Text(
                "${item.name} adlı öğeyi arşivlemek istediğinizden emin misiniz?",
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false), // İptal et
                  child: const Text("İptal", style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true), // Onayla
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Arşivle"),
                ),
              ],
            ),
          );
          
          // Kullanıcı "Arşivle" dediğinde
          if (shouldArchive == true) {
            await _archiveItem(item);
            return true; // Widget'i kaldır
          } else {
            return false; // Widget'i koru
          }
        }
        return false;
      },
      child: LongPressDraggable<Item>(
        data: item,
        feedback: _buildFeedback(item),
        childWhenDragging: Opacity(opacity: 0.3, child: content),
        child: content,
      ),
    );
  }

  Future<void> _archiveItem(Item item) async {
    item.isArchived = true;
    await DatabaseHelper.instance.updateItem(item);
    await FirestoreService().syncItem(item);
    _loadItems();
    _showSnack("Arşivlendi");
  }

  // İkon seçme dialog'u
  void _showIconSelector(Item folder) {
    int selectedIconIndex = folder.iconData != null 
        ? _folderIcons.indexWhere((icon) => icon.codePoint == folder.iconData!.codePoint)
        : 0;
    int selectedColorIndex = folder.folderColor != null 
        ? _folderColors.indexWhere((color) => color.value == folder.folderColor!.value)
        : 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e), // Koyu tema rengi
          surfaceTintColor: Colors.transparent,
          title: const Text(
            "Klasör İkonu ve Rengi Seç", 
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                // İkon seçimi
                const Text(
                  "İkon Seç", 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: Colors.white
                  )
                ),
                const SizedBox(height: 10),
                Expanded(
                  flex: 3,
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 1,
                    ),
                    itemCount: _folderIcons.length,
                    itemBuilder: (context, index) {
                      final icon = _folderIcons[index];
                      final isSelected = index == selectedIconIndex;
                      return GestureDetector(
                        onTap: () => setState(() => selectedIconIndex = index),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Color(0xFFe94560).withValues(alpha: 0.3) 
                                : Color(0xFF16213e).withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected 
                                ? Border.all(color: Color(0xFFe94560), width: 2) 
                                : Border.all(color: Color(0xFF0f3460).withValues(alpha: 0.3)),
                          ),
                          child: Icon(
                            icon,
                            color: isSelected ? Color(0xFFe94560) : Colors.white70,
                            size: 24,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // Renk seçimi
                const Text(
                  "Renk Seç", 
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: Colors.white
                  )
                ),
                const SizedBox(height: 10),
                Expanded(
                  flex: 1,
                  child: Row(
                    children: List.generate(_folderColors.length, (index) {
                      final color = _folderColors[index];
                      final isSelected = index == selectedColorIndex;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => selectedColorIndex = index),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            height: 50,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(12),
                              border: isSelected 
                                  ? Border.all(color: Colors.white, width: 3) 
                                  : Border.all(color: Color(0xFF0f3460).withValues(alpha: 0.5)),
                              boxShadow: isSelected ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.7),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ] : null,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
              child: const Text("İptal"),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  // Veritabanını güncelle
                  folder.iconData = _folderIcons[selectedIconIndex];
                  folder.folderColor = _folderColors[selectedColorIndex];
                  await DatabaseHelper.instance.updateItem(folder);
                  await FirestoreService().syncItem(folder);
                  
                  // Önce dialog'u kapat
                  if (mounted) Navigator.pop(context);
                  
                  // Ana listedeki klasörü bul ve güncelle
                  _updateFolderInList(folder);
                } catch (e) {
                  print("Kaydetme hatası: $e");
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Hata: $e"), 
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFFe94560),
                foregroundColor: Colors.white,
              ),
              child: const Text("Kaydet"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedback(Item item) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(item.name, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  // --- Mantıksal İşlemler ---
  
  // Klasörü listede bul ve güncelle
  void _updateFolderInList(Item updatedFolder) {
    bool found = false;
    
    // Ana seviyede ara
    for (var item in _rootItems) {
      if (item.id == updatedFolder.id) {
        item.iconData = updatedFolder.iconData;
        item.folderColor = updatedFolder.folderColor;
        found = true;
        break;
      }
      
      // Alt klasörlerde ara
      if (item.isFolder) {
        found = _updateFolderInChildren(item, updatedFolder);
        if (found) break;
      }
    }
    
    if (found && mounted) {
      setState(() {});
    }
  }
  
  // Alt klasörlerde recursive ara
  bool _updateFolderInChildren(Item parent, Item updatedFolder) {
    for (var child in parent.children) {
      if (child.id == updatedFolder.id) {
        // Doğrudan referansları güncelle
        child.iconData = updatedFolder.iconData;
        child.folderColor = updatedFolder.folderColor;
        print("Alt klasör güncellendi: ${child.name}, ikon: ${child.iconData?.codePoint}");
        return true;
      }
      
      if (child.isFolder) {
        bool found = _updateFolderInChildren(child, updatedFolder);
        if (found) return true;
      }
    }
    return false;
  }

  Future<void> _moveItem(Item draggedItem, String? newParentId) async {
    if (draggedItem.id == newParentId) return;
    draggedItem.parentId = newParentId;
    await DatabaseHelper.instance.updateItem(draggedItem);
    await FirestoreService().syncItem(draggedItem);
    _loadItems();
  }

  void _cyclePriority(Item item) async {
    if (item.isFolder) return;
    setState(() => item.priority = (item.priority + 1) % 3);
    await DatabaseHelper.instance.updateItem(item);
    await FirestoreService().syncItem(item);
    // _loadItems() çağrılmıyor - sıralama korunuyor
  }

  Future<void> _pushToCloud() async {
    try {
      List<Item> localItems = await DatabaseHelper.instance.getAllItems();
      for (var item in localItems) {
        await FirestoreService().syncItem(item);
      }
      _showSnack("Bulut güncellendi!");
    } catch (e) { _showSnack("Hata: $e"); }
  }

  Future<void> _pullFromCloud() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      var snapshot = await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('items').get();
      for (var doc in snapshot.docs) {
        await DatabaseHelper.instance.upsertItem(Item.fromMap(doc.data()));
      }
      _loadItems();
      _showSnack("Veriler çekildi!");
    } catch (e) { _showSnack("Hata: $e"); }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _setReminder(Item item) async {
    DateTime? pickedDate = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2030));
    if (pickedDate != null) {
      TimeOfDay? pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (pickedTime != null) {
        final selected = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
        setState(() => item.reminder = selected);
        await DatabaseHelper.instance.updateItem(item);
        await FirestoreService().syncItem(item);
        Add2Calendar.addEvent2Cal(Event(title: item.name, startDate: selected, endDate: selected.add(const Duration(minutes: 30))));
        // _loadItems() çağrılmıyor - sıralama korunuyor
      }
    }
  }

  Future<void> _addItem({String? parentId, bool isFolder = false}) async {
    print("_addItem çağrıldı - isFolder: $isFolder, parentId: $parentId");
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isFolder ? "Yeni Klasör" : "Yeni Not"),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: "Başlık girin...")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İptal")),
          TextButton(onPressed: () async {
            print("Ekle butonuna basıldı - text: '${controller.text}'");
            if (controller.text.isNotEmpty) {
              try {
                Item newItem = Item(id: const Uuid().v4(), name: controller.text, isFolder: isFolder, parentId: parentId);
                print("Item oluşturuldu: ${newItem.name}");
                await DatabaseHelper.instance.insertItem(newItem);
                print("Veritabanına eklendi");
                await FirestoreService().syncItem(newItem);
                print("Firestore'a sync edildi");
                if (ctx.mounted) Navigator.pop(ctx);
                _loadItems();
                _createController.play();
                print("İşlem tamamlandı");
              } catch (e) {
                print("Ekleme hatası: $e");
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            }
          }, child: const Text("Ekle")),
        ],
      ),
    );
  }
}

// ================= Archive Page =================
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});
  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<Item> _archivedItems = [];
  late ConfettiController _restoreController;

  @override
  void initState() {
    super.initState();
    _restoreController = ConfettiController(duration: const Duration(milliseconds: 600));
    _loadArchivedItems();
  }

  @override
  void dispose() {
    _restoreController.dispose();
    super.dispose();
  }

  Future<void> _loadArchivedItems() async {
    // Arşivlenmiş öğeleri yükle
    final items = await DatabaseHelper.instance.getArchivedItems();
    if (mounted) setState(() => _archivedItems = items);
  }

  Future<void> _restoreItem(Item item) async {
    _restoreController.play();
    // Öğeyi geri yükle - isArchived flag'ini false yap
    item.isArchived = false;
    await DatabaseHelper.instance.updateItem(item);
    await FirestoreService().syncItem(item);
    _showSnack("Öğe geri yüklendi");
    _loadArchivedItems();
    
    // Ana sayfanın güncellenmesi için
    if (mounted) {
      // Ana sayfaya geri dön ve listeyi yenile
      Navigator.pop(context);
      // Ana sayfadaki _loadItems() çağrısını tetikle
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Ana sayfadaki listeyi güncellemek için bir yol bulalım
        if (Navigator.canPop(context)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const FolderPage()),
          );
        }
      });
    }
  }

  Future<void> _deletePermanently(Item item) async {
    await DatabaseHelper.instance.deleteItem(item.id);
    await FirestoreService().deleteItem(item.id);
    _loadArchivedItems();
    _showSnack("Kalıcı olarak silindi");
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Arşiv", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1a1a2e),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1a1a2e),
              const Color(0xFF16213e),
              const Color(0xFF0f3460),
            ],
          ),
        ),
        child: _archivedItems.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.archive_outlined, size: 80, color: Colors.white54),
                    SizedBox(height: 20),
                    Text(
                      "Arşivde hiç öğe yok",
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      "Öğeleri sağa kaydırarak arşivleyebilirsiniz",
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _archivedItems.length,
                itemBuilder: (context, index) {
                  final item = _archivedItems[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: Colors.white.withValues(alpha: 0.9),
                    child: ListTile(
                      leading: Icon(
                        item.isFolder ? Icons.folder : Icons.note,
                        color: Colors.orange,
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(
                          color: Color(0xFF1a1a2e),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: item.isFolder 
                          ? Text("Klasör", style: TextStyle(color: Colors.grey[600]))
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restore, color: Colors.green),
                            onPressed: () => _restoreItem(item),
                            tooltip: "Geri Yükle",
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            onPressed: () => _deletePermanently(item),
                            tooltip: "Kalıcı Sil",
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: Align(
        alignment: Alignment.bottomCenter,
        child: ConfettiWidget(
          confettiController: _restoreController,
          blastDirectionality: BlastDirectionality.explosive,
        ),
      ),
    );
  }
}