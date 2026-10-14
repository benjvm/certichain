import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/features/verification/data/blockchain_models.dart';
import 'package:mobile/features/verification/data/platform_comparison_pdf_picker.dart';
import 'package:mobile/features/verification/data/protocol_opening_tools.dart';
import 'package:mobile/features/verification/data/sha256_pdf_hasher.dart';
import 'package:mobile/features/verification/domain/blockchain_verification.dart';

void main() => runApp(const MaterialApp(home: NativeOpeningProbe()));

class NativeOpeningProbe extends StatefulWidget {
  const NativeOpeningProbe({super.key});
  @override
  State<NativeOpeningProbe> createState() => _NativeOpeningProbeState();
}

class _NativeOpeningProbeState extends State<NativeOpeningProbe> {
  final tools = ProtocolOpeningTools();
  late final opening = tools.parse(
    const String.fromEnvironment('PHASE9E_OPENING'),
  );
  late final evidence = decodeEvidence(
    jsonDecode(const String.fromEnvironment('PHASE9E_EVIDENCE')),
    opening.code,
  );
  final stages = const [
    'Cancel JSON import',
    'Cancel JSON export',
    'Export synthetic opening',
    'Import exported opening',
    'Cancel PDF selection',
    'Select original PDF',
    'Select altered PDF',
  ];
  int stage = 0;
  bool busy = false, failed = false;
  Future<void> probe() async {
    setState(() => busy = true);
    try {
      switch (stage) {
        case 0:
          if (await tools.pickJson() != null) throw StateError('Cancellation');
        case 1:
          if (await tools.export(opening)) throw StateError('Cancellation');
        case 2:
          if (!await tools.export(opening)) throw StateError('Export');
        case 3:
          final source = await tools.pickJson();
          if (source == null ||
              tools.serialize(tools.parse(source)) !=
                  tools.serialize(opening)) {
            throw StateError('Import');
          }
        case 4:
          if (await PlatformComparisonPdfPicker().pick() != null) {
            throw StateError('Cancellation');
          }
        case 5 || 6:
          final selected = await PlatformComparisonPdfPicker().pick();
          if (selected == null) throw StateError('Selection');
          final hash = await Sha256PdfHasher().hash(
            selected,
            isCancelled: () => false,
          );
          final result = checkOpening(opening, opening.code, hash, evidence);
          if (result.validity !=
              (stage == 5
                  ? OpeningValidity.match
                  : OpeningValidity.pdfMismatch)) {
            throw StateError('Integrity');
          }
      }
      stage++;
    } catch (error) {
      debugPrint(
        'Native files failure stage=$stage category=${error is PlatformException
            ? 'platform'
            : error is FormatException
            ? 'format'
            : error is StateError
            ? 'state'
            : 'other'}',
      );
      failed = true;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    tools.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ElevatedButton(
          onPressed: busy || failed || stage == stages.length ? null : probe,
          child: Text(
            failed
                ? 'FAIL native opening files'
                : stage == stages.length
                ? 'PASS native opening files'
                : stages[stage],
          ),
        ),
      ),
    ),
  );
}
