import 'dart:convert';
import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:Intellisys/features/sale_forms/xlsx/simple_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lê o ZIP pelo diretório central (como o Excel faz) e devolve
/// nome → conteúdo descompactado, conferindo o CRC de cada entrada.
Map<String, String> _unzip(Uint8List bytes) {
  final bd = ByteData.sublistView(bytes);
  final eocd = bytes.length - 22;
  expect(bd.getUint32(eocd, Endian.little), 0x06054b50);
  final count = bd.getUint16(eocd + 10, Endian.little);
  var p = bd.getUint32(eocd + 16, Endian.little);
  final out = <String, String>{};
  for (var i = 0; i < count; i++) {
    expect(bd.getUint32(p, Endian.little), 0x02014b50);
    final crc = bd.getUint32(p + 16, Endian.little);
    final compSize = bd.getUint32(p + 20, Endian.little);
    final size = bd.getUint32(p + 24, Endian.little);
    final nameLen = bd.getUint16(p + 28, Endian.little);
    final local = bd.getUint32(p + 42, Endian.little);
    final name = utf8.decode(bytes.sublist(p + 46, p + 46 + nameLen));
    expect(bd.getUint32(local, Endian.little), 0x04034b50);
    final localName = bd.getUint16(local + 26, Endian.little);
    final dataStart = local + 30 + localName;
    final comp = bytes.sublist(dataStart, dataStart + compSize);
    final raw = ZLibDecoder(raw: true).convert(comp);
    expect(raw.length, size, reason: name);
    expect(crc32(raw), crc, reason: name);
    out[name] = utf8.decode(raw);
    p += 46 + nameLen;
  }
  return out;
}

void main() {
  test('CRC-32 do ZIP (vetor de referência)', () {
    expect(crc32(ascii.encode('123456789')), 0xCBF43926);
    expect(crc32(const []), 0);
  });

  test('colunas A, Z, AA, AZ, BA', () {
    expect(xlsxColumnName(0), 'A');
    expect(xlsxColumnName(25), 'Z');
    expect(xlsxColumnName(26), 'AA');
    expect(xlsxColumnName(51), 'AZ');
    expect(xlsxColumnName(52), 'BA');
  });

  test('escape de XML e remoção de caracteres de controle', () {
    expect(xlsxEscape('a & b < c > "d"'), 'a &amp; b &lt; c &gt; &quot;d&quot;');
    expect(xlsxEscape('x\u0001y\nz'), 'xy\nz');
  });

  test('nome de aba válido', () {
    expect(xlsxSafeSheetName('Relatório: fichas/2026'), 'Relatório  fichas 2026');
    expect(xlsxSafeSheetName('  '), 'Planilha');
    expect(xlsxSafeSheetName('x' * 40).length, 31);
  });

  test('pacote XLSX com as partes obrigatórias e as células', () {
    final bytes = buildXlsx([
      XlsxSheet(
        name: 'Aba 1',
        rows: [
          ['Nome', 'Valor'],
          ['Ana & Cia', 12.5],
          ['Ação', null],
        ],
        columnWidths: const [20, 10],
      ),
      XlsxSheet(name: 'Aba 1', rows: [['repetida']], headerRow: false),
    ]);
    // Assinatura "PK".
    expect(bytes.sublist(0, 2), [0x50, 0x4B]);
    final files = _unzip(bytes);
    expect(files.keys, containsAll([
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'xl/styles.xml',
      'xl/worksheets/sheet1.xml',
      'xl/worksheets/sheet2.xml',
    ]));
    final wb = files['xl/workbook.xml']!;
    expect(wb, contains('name="Aba 1"'));
    expect(wb, contains('name="Aba 1 (2)"'));
    final s1 = files['xl/worksheets/sheet1.xml']!;
    expect(s1, contains('<c r="A1" t="inlineStr" s="1">'));
    expect(s1, contains('Ana &amp; Cia'));
    expect(s1, contains('<c r="B2" s="2"><v>12.5</v></c>'));
    expect(s1, contains('Ação'));
    expect(s1, isNot(contains('r="B3"')));
    expect(s1, contains('state="frozen"'));
    expect(files['xl/worksheets/sheet2.xml'], isNot(contains('frozen')));
  });
}
