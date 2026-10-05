import 'package:flutter/material.dart';
import 'package:mobile/app/verification_scanner.dart';
import 'package:mobile/features/verification/domain/verification_link.dart';
import 'package:mobile/features/verification/presentation/qr_scanner_panel.dart';

// Complementary native adapter probe, never imported by lib/main.dart.
void main() => runApp(const MaterialApp(home: NativeCameraProbe()));

class NativeCameraProbe extends StatefulWidget {
  const NativeCameraProbe({super.key});
  @override
  State<NativeCameraProbe> createState() => _NativeCameraProbeState();
}

class _NativeCameraProbeState extends State<NativeCameraProbe> {
  bool scanning = false;
  bool confirmed = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () => setState(() => scanning = true),
              child: const Text('Open production scanner'),
            ),
            if (confirmed) const Text('Confirmed code'),
            if (scanning)
              QrScannerPanel(
                link: VerificationLink('https://certichain.example/'),
                createSession: createScannerSession,
                onClose: () => setState(() => scanning = false),
                onCode: (_) => setState(() {
                  scanning = false;
                  confirmed = true;
                }),
              ),
          ],
        ),
      ),
    ),
  );
}
