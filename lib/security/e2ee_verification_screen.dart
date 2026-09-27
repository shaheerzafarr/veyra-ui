import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/theme/app_theme.dart';
import 'e2ee_service.dart';
import 'models/e2ee_models.dart';

class E2eeVerificationScreen extends ConsumerStatefulWidget {
  const E2eeVerificationScreen({
    required this.contactName,
    required this.remote,
    super.key,
  });

  final String contactName;
  final DeviceAddress remote;

  @override
  ConsumerState<E2eeVerificationScreen> createState() =>
      _E2eeVerificationScreenState();
}

class _E2eeVerificationScreenState
    extends ConsumerState<E2eeVerificationScreen> {
  late Future<IdentityVerification> _verification;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _verification =
        ref.read(e2eeServiceProvider).getSafetyNumber(widget.remote);
  }

  Future<void> _scan() async {
    final encoded = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _SafetyQrScanner()),
    );
    if (encoded == null || !mounted) return;
    var verified = false;
    try {
      verified = await ref.read(e2eeServiceProvider).verifyScannable(
            widget.remote,
            base64Decode(encoded),
          );
    } on FormatException {
      verified = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(verified
          ? '${widget.contactName} verified on this device'
          : 'The scanned security code did not match'),
    ));
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verify encryption')),
        body: FutureBuilder<IdentityVerification>(
          future: _verification,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Exchange an encrypted message before verifying this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: VeyraColors.muted),
                  ),
                ),
              );
            }
            final verification = snapshot.data;
            if (verification == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final groups = RegExp(r'.{1,5}')
                .allMatches(verification.display)
                .map((match) => match.group(0)!)
                .join(' ');
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Icon(
                  verification.verified
                      ? Icons.verified_user_rounded
                      : Icons.shield_outlined,
                  size: 52,
                  color: VeyraColors.emerald,
                ),
                const SizedBox(height: 12),
                Text(
                  verification.verified
                      ? 'Device verified'
                      : 'Compare security codes',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Compare these numbers in person or scan the QR code shown '
                  'on the other device. Verification is stored locally.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VeyraColors.muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                Card(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Center(
                      child: QrImageView(
                        data: base64Encode(verification.scannable),
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SelectableText(
                  groups,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    height: 1.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan their code'),
                ),
              ],
            );
          },
        ),
      );
}

class _SafetyQrScanner extends StatefulWidget {
  const _SafetyQrScanner();

  @override
  State<_SafetyQrScanner> createState() => _SafetyQrScannerState();
}

class _SafetyQrScannerState extends State<_SafetyQrScanner> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan security code')),
        body: MobileScanner(
          onDetect: (capture) {
            if (_handled) return;
            final value = capture.barcodes
                .map((barcode) => barcode.rawValue)
                .whereType<String>()
                .firstOrNull;
            if (value == null) return;
            _handled = true;
            Navigator.of(context).pop(value);
          },
        ),
      );
}
