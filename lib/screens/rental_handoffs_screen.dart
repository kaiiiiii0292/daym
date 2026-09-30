import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/equipment_repository.dart';
import '../theme.dart';

class RentalHandoffsScreen extends StatefulWidget {
  const RentalHandoffsScreen({
    super.key,
    required this.repository,
    required this.profile,
  });

  final EquipmentRepository repository;
  final Map<String, dynamic>? profile;

  @override
  State<RentalHandoffsScreen> createState() => _RentalHandoffsScreenState();
}

class _RentalHandoffsScreenState extends State<RentalHandoffsScreen> {
  List<RentalHandoff> _rentals = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rentals = await widget.repository.myRentalHandoffs();
      if (!mounted) return;
      setState(() {
        _rentals = rentals;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your rentals. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My rentals')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _MessageState(
                    message: _error!,
                    action: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text(
                          'Handoffs',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'The QR holder displays the code. The other verified participant scans it and takes the condition photo.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 18),
                        if (_rentals.isEmpty)
                          const _MessageState(
                            icon: Icons.receipt_long_outlined,
                            message: 'No rentals to hand off yet.',
                          )
                        else
                          ..._rentals.map((rental) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _RentalHandoffCard(
                                  rental: rental,
                                  profileId: widget.profile?['id'] as String?,
                                  onOpen: () async {
                                    await Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => HandoffScreen(
                                          repository: widget.repository,
                                          rental: rental,
                                        ),
                                      ),
                                    );
                                    if (mounted) _load();
                                  },
                                ),
                              )),
                      ],
                    ),
                  ),
      );
}

class _RentalHandoffCard extends StatelessWidget {
  const _RentalHandoffCard({
    required this.rental,
    required this.profileId,
    required this.onOpen,
  });

  final RentalHandoff rental;
  final String? profileId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final borrowerIsCurrentUser = profileId == rental.borrowerId;
    final handoffReady = rental.paymentStatus == 'paid' &&
        (rental.status == 'confirmed' || rental.status == 'active');
    final phase = rental.pickupVerifiedAt == null ? 'Pickup' : 'Return';
    final remaining = rental.dueTimestamp.difference(DateTime.now());
    final returnUrgent = borrowerIsCurrentUser &&
        rental.status == 'active' &&
        remaining <= const Duration(minutes: 30);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.inventory_2_outlined, color: FlexShareTheme.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rental.itemTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StateTag(status: rental.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${rental.durationCount} ${rental.durationType == 'hourly' ? 'hour(s)' : 'day(s)'} · Due ${TimeOfDay.fromDateTime(rental.dueTimestamp).format(context)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (rental.paymentStatus != 'paid') ...[
              const SizedBox(height: 10),
              const Text(
                'Payment is pending provider confirmation. Handoff QR unlocks after payment.',
                style: TextStyle(color: Color(0xFF92400E), fontSize: 12),
              ),
            ],
            if (returnUrgent) ...[
              const SizedBox(height: 12),
              _ReturnAlert(dueTimestamp: rental.dueTimestamp),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: handoffReady ? onOpen : null,
                icon: Icon(
                  rental.returnVerifiedAt != null
                      ? Icons.check_circle_outline
                      : Icons.qr_code_scanner,
                ),
                label: Text(
                  rental.returnVerifiedAt != null
                      ? 'Handoff complete'
                      : handoffReady
                          ? '$phase handoff'
                          : 'Waiting for confirmation',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HandoffScreen extends StatefulWidget {
  const HandoffScreen({
    super.key,
    required this.repository,
    required this.rental,
  });

  final EquipmentRepository repository;
  final RentalHandoff rental;

  @override
  State<HandoffScreen> createState() => _HandoffScreenState();
}

class _HandoffScreenState extends State<HandoffScreen> {
  Map<String, dynamic>? _handoffCode;
  bool _loading = true;
  bool _scanning = false;
  DateTime? _verifiedAt;
  String? _verifiedPhase;
  Timer? _clock;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCode();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _loadCode() async {
    try {
      final code = await widget.repository.getRentalHandoffQr(widget.rental.rentalId);
      if (!mounted) return;
      setState(() {
        _handoffCode = code;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is PostgrestException
            ? error.message
            : 'Ask the other handoff participant to open this rental and display their QR code.';
      });
    }
  }

  Future<void> _scanAndVerify() async {
    final scannedToken = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerScreen()),
    );
    if (scannedToken == null || !mounted) return;

    final phase = _handoffCode?['out_phase'] as String? ??
      (widget.rental.pickupVerifiedAt == null ? 'pickup' : 'return');
    setState(() => _scanning = true);

    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1600,
      );
      if (photo == null) {
        setState(() => _scanning = false);
        return;
      }
      final path = await widget.repository.uploadHandoffPhoto(
        rentalId: widget.rental.rentalId,
        phase: phase,
        image: photo,
      );
      final verifiedAt = await widget.repository.verifyRentalHandoff(
        rentalId: widget.rental.rentalId,
        token: scannedToken,
        phase: phase,
        photoPath: path,
      );
      if (!mounted) return;
      setState(() {
        _verifiedAt = verifiedAt;
        _verifiedPhase = phase;
        _scanning = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = error is PostgrestException
            ? error.message
            : 'Could not verify this handoff. Confirm the other participant’s QR and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _handoffCode?['out_phase'] as String?;
    final due = _displayDue;
    final remaining = due.difference(DateTime.now());
    final isReturn = _verifiedPhase == 'return' ||
      phase == 'return' ||
      widget.rental.pickupVerifiedAt != null;

    return Scaffold(
      appBar: AppBar(title: const Text('QR handoff')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.rental.itemTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            isReturn ? 'Return condition check' : 'Pickup condition check',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (_verifiedAt != null)
            _VerifiedBanner(
              title: isReturn ? 'Return verified' : 'Pickup verified · Rental active',
              detail: isReturn
                  ? 'The after-condition photo has been saved.'
                  : 'The before-condition photo has been saved.',
            )
          else if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ))
          else if (_handoffCode != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(Icons.qr_code_2, color: FlexShareTheme.navy, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'Let the other participant scan this one-time code.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: FlexShareTheme.white,
                      child: QrImageView(
                        data: _handoffCode!['out_token'] as String,
                        size: 210,
                        backgroundColor: FlexShareTheme.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isReturn ? 'Return QR' : 'Pickup QR',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: _scanning ? null : _scanAndVerify,
                icon: _scanning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.qr_code_scanner),
                label: Text(_scanning ? 'Saving condition photo…' : 'Scan partner QR and take photo'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A camera photo is required after scanning. Pickup saves the before photo; return saves the after photo.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MessageState(message: _error!),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _scanning ? null : _scanAndVerify,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan the other participant’s QR'),
                ),
                TextButton.icon(
                  onPressed: _loadCode,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload QR'),
                ),
              ],
            ),
          if (_error != null && _handoffCode != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
          ],
          const SizedBox(height: 18),
          if (!_isComplete && widget.rental.status == 'active')
            _ReturnAlert(dueTimestamp: due, now: DateTime.now(), remaining: remaining),
          if (_verifiedAt != null) ...[
            const SizedBox(height: 18),
            _VerifiedBanner(
              title: 'Recorded ${TimeOfDay.fromDateTime(_verifiedAt!).format(context)}',
              detail: isReturn
                  ? 'Both condition photos are saved. The item is marked available again.'
                  : 'The return countdown is active. Reopen this rental to display the new return QR.',
            ),
          ],
        ],
      ),
    );
  }

  bool get _isComplete =>
      widget.rental.returnVerifiedAt != null || _verifiedPhase == 'return';

  DateTime get _displayDue {
    if (_verifiedPhase == 'pickup' && _verifiedAt != null) {
      final duration = widget.rental.durationType == 'hourly'
          ? Duration(hours: widget.rental.durationCount)
          : Duration(days: widget.rental.durationCount);
      return _verifiedAt!.add(duration);
    }
    return widget.rental.dueTimestamp;
  }
}

class _QrScannerScreen extends StatefulWidget {
  const _QrScannerScreen();

  @override
  State<_QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<_QrScannerScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _returned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_returned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _returned = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan handoff QR')),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  border: Border.all(color: FlexShareTheme.mint, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 40,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: FlexShareTheme.charcoal.withAlpha(220),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Hold the other participant’s QR inside the frame.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: FlexShareTheme.white),
                ),
              ),
            ),
          ],
        ),
      );
}

class _VerifiedBanner extends StatelessWidget {
  const _VerifiedBanner({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFD1FAE5),
          border: Border.all(color: FlexShareTheme.mint),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.verified_rounded, color: Color(0xFF047857)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(detail, style: const TextStyle(color: Color(0xFF064E3B))),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ReturnAlert extends StatelessWidget {
  const _ReturnAlert({
    required this.dueTimestamp,
    this.now,
    this.remaining,
  });

  final DateTime dueTimestamp;
  final DateTime? now;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final duration = remaining ?? dueTimestamp.difference(now ?? DateTime.now());
    final late = duration.isNegative;
    final absolute = duration.abs();
    final time = '${absolute.inHours > 0 ? '${absolute.inHours}h ' : ''}'
        '${absolute.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        border: Border.all(color: FlexShareTheme.amber),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              late
                  ? 'Return is overdue by $time. Please contact the lender.'
                  : 'Return due in $time. Bring the item back on time to avoid late fees.',
              style: const TextStyle(
                color: Color(0xFF78350F),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateTag extends StatelessWidget {
  const _StateTag({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => FlexShareTheme.amber,
      'completed' => FlexShareTheme.mint,
      _ => FlexShareTheme.navy,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: FlexShareTheme.statusPill(color),
      child: Text(
        status[0].toUpperCase() + status.substring(1),
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({required this.message, this.icon, this.action});

  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 36, color: const Color(0xFF64748B)),
            if (icon != null) const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      );
}