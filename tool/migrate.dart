// Aplica supabase/migrations/*.sql al proyecto de Supabase, en orden y una transacción por archivo.
//
//   dart run tool/migrate.dart            # aplica todas
//   dart run tool/migrate.dart --file 20261026000000_document_number_sequence_integrity.sql
//   dart run tool/migrate.dart --dry-run  # solo lista
//   dart run tool/migrate.dart --reset    # BORRA el esquema public (y sus datos) y aplica todas
//
// Usa DATABASE_URL (variable de entorno o archivo .env): Supabase > Connect > Session pooler.
import 'dart:io';

import 'package:postgres/postgres.dart';

String? _readDatabaseUrl() {
  final fromEnv = Platform.environment['DATABASE_URL'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('DATABASE_URL=')) {
      return line
          .substring('DATABASE_URL='.length)
          .trim()
          .replaceAll(RegExp('^["\']|["\']\$'), '');
    }
  }
  return null;
}

Future<void> main(List<String> args) async {
  final files =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final fileOptionIndex = args.indexOf('--file');
  if (fileOptionIndex >= 0) {
    if (fileOptionIndex + 1 >= args.length) {
      stderr.writeln('Falta el nombre de archivo después de --file.');
      exit(64);
    }
    if (args.contains('--reset')) {
      stderr.writeln('--file no se puede combinar con --reset.');
      exit(64);
    }
    final selectedName = args[fileOptionIndex + 1];
    final selectedFiles = files
        .where((f) => f.uri.pathSegments.last == selectedName)
        .toList();
    if (selectedFiles.isEmpty) {
      stderr.writeln('No existe una migración con ese nombre: $selectedName');
      exit(64);
    }
    files
      ..clear()
      ..addAll(selectedFiles);
  }
  if (args.contains('--dry-run')) {
    for (final f in files) {
      stdout.writeln(f.uri.pathSegments.last);
    }
    return;
  }
  final url = _readDatabaseUrl();
  if (url == null) {
    stderr.writeln('Falta DATABASE_URL (variable de entorno o .env).');
    exit(64);
  }
  final uri = Uri.parse(url);
  final user = Uri.decodeComponent(uri.userInfo.split(':').first);
  final password = Uri.decodeComponent(
    uri.userInfo.substring(uri.userInfo.indexOf(':') + 1),
  );
  final conn = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.path.replaceFirst('/', ''),
      username: user,
      password: password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.require),
  );
  var failed = false;
  try {
    if (args.contains('--reset')) {
      await conn.runTx(
        (tx) => tx.execute('''
        drop schema if exists public cascade;
        create schema public;
        alter schema public owner to postgres;
        grant usage on schema public to postgres, anon, authenticated, service_role;
        grant all on schema public to postgres, service_role;
        alter default privileges in schema public grant all on tables to postgres, service_role;
        alter default privileges in schema public grant all on functions to postgres, service_role;
        alter default privileges in schema public grant all on sequences to postgres, service_role;
      ''', queryMode: QueryMode.simple),
      );
      stdout.writeln('RESET esquema public recreado');
    }
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      try {
        await conn.runTx(
          (tx) => tx.execute(f.readAsStringSync(), queryMode: QueryMode.simple),
        );
        stdout.writeln('OK   $name');
      } catch (e) {
        failed = true;
        stderr.writeln('FAIL $name -> ${e.toString().split('\n').first}');
        break; // cada archivo es una transacción revertida; no se continúa con los siguientes
      }
    }
  } finally {
    await conn.close();
  }
  if (failed) exit(1);
}
