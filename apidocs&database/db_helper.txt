import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

enum DBType {
  metadata,
  uthmani15,
  uthmani,
}

class DBHelper {
  static final Map<DBType, Database> _dbInstances = {};

  static Future<Database> openDB(DBType type) async {
    if (_dbInstances.containsKey(type)) {
      return _dbInstances[type]!;
    }

    // mapping lokasi assets + nama database
    final dbConfig = {
      DBType.metadata: {
        "asset": "assets/data/quran-metadata-surah-name.sqlite",
        "name": "quran-metadata-surah-name.sqlite"
      },
      DBType.uthmani15: {
        "asset": "assets/data/uthmani-15-lines.db",
        "name": "uthmani-15-lines.db"
      },
      DBType.uthmani: {
        "asset": "assets/data/uthmani.db",
        "name": "uthmani.db"
      },
    };

    final assetPath = dbConfig[type]!["asset"]!;
    final dbName = dbConfig[type]!["name"]!;

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbName);

    // cek kalau belum ada → copy dari assets
    if (!await databaseExists(path)) {
      await Directory(dirname(path)).create(recursive: true);
      ByteData data = await rootBundle.load(assetPath);
      List<int> bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await File(path).writeAsBytes(bytes, flush: true);
    }

    final db = await openDatabase(path);
    _dbInstances[type] = db;
    return db;
  }

  // TAMBAHAN: Method untuk menutup semua database
  static Future<void> closeAllDatabases() async {
    for (final db in _dbInstances.values) {
      await db.close();
    }
    _dbInstances.clear();
  }

  // TAMBAHAN: Method untuk reset database (jika diperlukan)
  static Future<void> resetDatabase(DBType type) async {
    if (_dbInstances.containsKey(type)) {
      await _dbInstances[type]!.close();
      _dbInstances.remove(type);
    }
    
    final dbConfig = {
      DBType.metadata: "quran-metadata-surah-name.sqlite",
      DBType.uthmani15: "uthmani-15-lines.db", 
      DBType.uthmani: "uthmani.db",
    };

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, dbConfig[type]!);
    
    if (await databaseExists(path)) {
      await deleteDatabase(path);
    }
  }
}