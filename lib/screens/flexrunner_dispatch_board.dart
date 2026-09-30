import 'dart:async';

import 'package:flutter/material.dart';

import '../data/equipment_repository.dart';
import '../theme.dart';
import 'rental_handoffs_screen.dart';

class FlexRunnerDispatchBoard extends StatefulWidget {
  const FlexRunnerDispatchBoard({
    super.key,
    required this.repository,
    required this.profile,
  });

  final EquipmentRepository repository;
  final Map<String, dynamic>? profile;

  @override
  State<FlexRunnerDispatchBoard> createState() => _FlexRunnerDispatchBoardState();
}

class _FlexRunnerDispatchBoardState extends State<FlexRunnerDispatchBoard> {
  List<DeliveryJob> _jobs = const [];
  List<RentalHandoff> _handoffs = const [];
  bool _loading = true;
  String? _error;
  String? _workingId;

  @override
  void initState() {
    super.initState();
    widget.repository.watchDeliveryChanges(() {
      if (mounted) _load(showLoader: false);
    });
    _load();
  }

  @override
  void dispose() {
    unawaited(widget.repository.stopWatchingDeliveryChanges());
    super.dispose();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        widget.repository.flexrunnerDeliveries(),
        widget.repository.myRentalHandoffs(),
      ]);
      final jobs = results[0] as List<DeliveryJob>;
      final handoffs = results[1] as List<RentalHandoff>;
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _handoffs = handoffs;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().contains('verified FlexRunner')
            ? 'PSU ID verification is required before you can accept campus runs.'
            : 'Could not load dispatch jobs. Pull down to try again.';
      });
    }
  }

  Future<void> _accept(DeliveryJob job) async {
    await _perform(job, () => widget.repository.acceptDelivery(job.id));
  }

  Future<void> _advance(DeliveryJob job) async {
    final next = job.status == 'assigned' ? 'picked_up' : 'delivered';
    await _perform(
      job,
      () => widget.repository.updateDeliveryStatus(job.id, next),
    );
  }

  Future<void> _verifyPickup(DeliveryJob job) async {
    RentalHandoff? handoff;
    for (final candidate in _handoffs) {
      if (candidate.rentalId == job.rentalId) {
        handoff = candidate;
        break;
      }
    }
    if (handoff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This rental handoff is not available to your account.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => HandoffScreen(
          repository: widget.repository,
          rental: handoff!,
        ),
      ),
    );
    if (mounted) await _load(showLoader: false);
  }

  Future<void> _perform(DeliveryJob job, Future<void> Function() action) async {
    setState(() {
      _workingId = job.id;
      _error = null;
    });
    try {
      await action();
      await _load(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workingId = null;
        _error = 'This job changed before your update. Refresh the board and try again.';
      });
    }
    if (mounted) setState(() => _workingId = null);
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Campus dispatch', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 5),
                  Text(
                    'Pick up between classes. Deliver straight to the classroom.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const TabBar(
              tabs: [
                Tab(text: 'Open jobs'),
                Tab(text: 'My runs'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _jobList(
                    _jobs.where((job) => job.status == 'open').toList(),
                    openJobs: true,
                  ),
                  _jobList(
                    _jobs.where((job) => job.status != 'open').toList(),
                    openJobs: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _jobList(List<DeliveryJob> jobs, {required bool openJobs}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _BoardMessage(
        message: _error!,
        action: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );
    }
    if (jobs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 280,
              child: _BoardMessage(
                icon: openJobs ? Icons.route_outlined : Icons.delivery_dining_outlined,
                message: openJobs
                    ? 'No open runs right now. New campus pickups will show up here.'
                    : 'You haven’t accepted a campus run yet.',
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        itemCount: jobs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _DeliveryCard(
          job: jobs[index],
          working: _workingId == jobs[index].id,
          onAccept: () => _accept(jobs[index]),
          onAdvance: () => _advance(jobs[index]),
          onVerifyHandoff: () => _verifyPickup(jobs[index]),
        ),
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.job,
    required this.working,
    required this.onAccept,
    required this.onAdvance,
    required this.onVerifyHandoff,
  });

  final DeliveryJob job;
  final bool working;
  final VoidCallback onAccept;
  final VoidCallback onAdvance;
  final VoidCallback onVerifyHandoff;

  @override
  Widget build(BuildContext context) {
    final nextStatus = job.status == 'assigned' ? 'picked_up' : 'delivered';
    final statusColor = switch (job.status) {
      'picked_up' => FlexShareTheme.amber,
      'delivered' => FlexShareTheme.mint,
      _ => FlexShareTheme.navy,
    };
    final statusLabel = switch (job.status) {
      'picked_up' => 'Picked Up',
      'delivered' => 'Delivered to Classroom',
      'assigned' => 'Assigned to you',
      _ => 'Open',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    job.itemTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                _DispatchStatus(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 14),
            _RouteLine(
              icon: Icons.circle_outlined,
              label: 'Pick up',
              location: job.pickupBuilding,
              color: FlexShareTheme.navy,
            ),
            const Padding(
              padding: EdgeInsets.only(left: 9),
              child: SizedBox(height: 14, child: VerticalDivider(width: 1)),
            ),
            _RouteLine(
              icon: Icons.location_on_outlined,
              label: 'Drop off',
              location: job.dropoffClassroom,
              color: FlexShareTheme.mint,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18, color: FlexShareTheme.charcoal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your courier payout',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  _formatPhp(job.payout),
                  style: FlexShareTheme.priceStyle(
                    Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: job.status == 'open'
                  ? FilledButton.icon(
                      onPressed: working ? null : onAccept,
                      icon: working
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.flash_on_outlined),
                      label: const Text('Accept run'),
                    )
                        : job.status == 'delivered'
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon: Icon(Icons.check_circle_outline),
                          label: Text('Delivered to Classroom'),
                        )
                      : job.status == 'assigned' && job.pickupVerifiedAt == null
                          ? OutlinedButton.icon(
                              onPressed: working ? null : onVerifyHandoff,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Verify Pickup QR'),
                            )
                          : FilledButton.icon(
                          style: job.status == 'picked_up'
                              ? FilledButton.styleFrom(
                                  backgroundColor: FlexShareTheme.amber,
                                  foregroundColor: FlexShareTheme.charcoal,
                                )
                              : null,
                          onPressed: working ? null : onAdvance,
                          icon: working
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(nextStatus == 'picked_up'
                                  ? Icons.inventory_2_outlined
                                  : Icons.task_alt_outlined),
                          label: Text(nextStatus == 'picked_up'
                              ? 'Mark Picked Up'
                              : 'Delivered to Classroom'),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine({
    required this.icon,
    required this.label,
    required this.location,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String location;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 9),
          SizedBox(
            width: 62,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              location,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
}

class _DispatchStatus extends StatelessWidget {
  const _DispatchStatus({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 132),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: FlexShareTheme.statusPill(color),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color == FlexShareTheme.amber
                ? const Color(0xFF78350F)
                : color == FlexShareTheme.mint
                    ? const Color(0xFF065F46)
                    : FlexShareTheme.navy,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _BoardMessage extends StatelessWidget {
  const _BoardMessage({required this.message, this.icon, this.action});

  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 38, color: const Color(0xFF64748B)),
              if (icon != null) const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 12), action!],
            ],
          ),
        ),
      );
}

String _formatPhp(double amount) =>
    '₱${amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)}';