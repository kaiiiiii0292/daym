import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../data/equipment_repository.dart';
import 'flexrunner_dispatch_board.dart';
import 'rental_handoffs_screen.dart';
import '../theme.dart';

enum FlexRole { borrower, lender, flexRunner }

extension _FlexRoleLabel on FlexRole {
  String get label => switch (this) {
        FlexRole.borrower => 'Borrower',
        FlexRole.lender => 'Lender',
        FlexRole.flexRunner => 'FlexRunner',
      };
}

FlexRole _roleFromProfile(Map<String, dynamic>? profile) => switch (profile?['role']) {
      'lender' => FlexRole.lender,
      'flexrunner' => FlexRole.flexRunner,
      _ => FlexRole.borrower,
    };

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({
    super.key,
    required this.repository,
    required this.profile,
    required this.demoMode,
  });

  final EquipmentRepository repository;
  final Map<String, dynamic>? profile;
  final bool demoMode;

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  late FlexRole _activeRole;
  final _searchController = TextEditingController();
  List<EquipmentItem> _items = const [];
  List<RentalHandoff> _myRentals = const [];
  String? _selectedBuilding;
  String _search = '';
  bool _loading = true;
  String? _loadError;
  Timer? _rentalTicker;
  Timer? _rentalRefresh;

  bool get _canPost => widget.demoMode ||
      (widget.profile?['role'] == 'lender' &&
          widget.profile?['is_id_verified'] == true);

  @override
  void initState() {
    super.initState();
    _activeRole = _roleFromProfile(widget.profile);
    _loadItems();
    widget.repository.watchListingChanges(() {
      if (mounted) _loadItems(showLoader: false);
    });
    if (widget.profile?['role'] == 'borrower') {
      _loadMyRentals();
      _rentalTicker = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) setState(() {});
      });
      _rentalRefresh = Timer.periodic(const Duration(minutes: 1), (_) {
        _loadMyRentals();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _rentalTicker?.cancel();
    _rentalRefresh?.cancel();
    unawaited(widget.repository.stopWatchingListingChanges());
    super.dispose();
  }

  Future<void> _loadItems({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final items = switch (_activeRole) {
        FlexRole.lender => await widget.repository.myListings(),
        FlexRole.flexRunner => const <EquipmentItem>[],
        FlexRole.borrower => await widget.repository.availableItems(),
      };
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load listings. Pull down to try again.';
      });
    }
  }

  Future<void> _loadMyRentals() async {
    try {
      final rentals = await widget.repository.myRentalHandoffs();
      if (mounted) setState(() => _myRentals = rentals);
    } catch (_) {
      // The reminder is supplementary; the rentals screen shows query failures.
    }
  }

  RentalHandoff? get _urgentBorrowerRental {
    final profileId = widget.profile?['id'] as String?;
    if (profileId == null) return null;
    final urgent = _myRentals.where((rental) {
      final remaining = rental.dueTimestamp.difference(DateTime.now());
      return rental.borrowerId == profileId &&
          rental.status == 'active' &&
          remaining <= const Duration(minutes: 30);
    }).toList()
      ..sort((left, right) => left.dueTimestamp.compareTo(right.dueTimestamp));
    return urgent.isEmpty ? null : urgent.first;
  }

  void _setRole(FlexRole? role) {
    if (role == null || role == _activeRole) return;
    setState(() {
      _activeRole = role;
      _selectedBuilding = null;
      _search = '';
      _searchController.clear();
    });
    _loadItems();
  }

  List<EquipmentItem> get _visibleItems {
    return _items.where((item) {
      if (_selectedBuilding != null && item.building != _selectedBuilding) {
        return false;
      }
      final query = _search.trim().toLowerCase();
      return query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query) ||
          item.building.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isLender = _activeRole == FlexRole.lender;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FlexShare'),
        actions: [
          _RoleSwitcher(value: _activeRole, onChanged: _setRole),
          IconButton(
            tooltip: 'My rentals and handoffs',
            onPressed: _openRentalHandoffs,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: 'Return reminders',
            onPressed: () => _showReminder(context),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined, color: FlexShareTheme.amber),
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: FlexShareTheme.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _activeRole == FlexRole.flexRunner
          ? FlexRunnerDispatchBoard(
              repository: widget.repository,
              profile: widget.profile,
            )
          : RefreshIndicator(
        onRefresh: () => _loadItems(showLoader: false),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
              sliver: SliverToBoxAdapter(
                child: _PageHeading(
                  role: _activeRole,
                  name: widget.profile?['full_name'] as String?,
                  demoMode: widget.demoMode,
                ),
              ),
            ),
            if (_activeRole == FlexRole.borrower && _urgentBorrowerRental != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: _ReturnReminderBanner(
                    rental: _urgentBorrowerRental!,
                    onTap: _openRentalHandoffs,
                  ),
                ),
              ),
            if (_activeRole == FlexRole.borrower) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: _CampusMapCard(
                    items: _items,
                    selectedBuilding: _selectedBuilding,
                    onBuildingSelected: (building) => setState(() {
                      _selectedBuilding = _selectedBuilding == building ? null : building;
                    }),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _BuildingFilter(
                  selectedBuilding: _selectedBuilding,
                  onSelected: (building) => setState(() {
                    _selectedBuilding = _selectedBuilding == building ? null : building;
                  }),
                ),
              ),
            ],
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _search = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: isLender
                        ? 'Search your listings'
                        : 'Try “calculator” or a campus building',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _search = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              sliver: SliverToBoxAdapter(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        isLender ? 'Your listings' : 'Available near you',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      '${_visibleItems.length} ${_visibleItems.length == 1 ? 'item' : 'items'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Listings unavailable',
                  detail: _loadError!,
                  action: TextButton.icon(
                    onPressed: _loadItems,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ),
              )
            else if (_visibleItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  icon: isLender ? Icons.inventory_2_outlined : Icons.search_off_outlined,
                  title: isLender ? 'No listings yet' : 'No gear at this spot yet',
                  detail: isLender
                      ? 'Post the calculator, camera, or lab gear in your bag.'
                      : 'Try another building or search for different equipment.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                sliver: SliverGrid.builder(
                  itemCount: _visibleItems.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _gridColumns(MediaQuery.sizeOf(context).width),
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 388,
                  ),
                  itemBuilder: (context, index) => _EquipmentCard(
                    item: _visibleItems[index],
                    lenderView: isLender,
                    onRent: () => _showRentInfo(_visibleItems[index]),
                    onAvailabilityChanged: (available) =>
                      _setAvailability(_visibleItems[index], available),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: isLender
          ? FloatingActionButton.extended(
              onPressed: _showPostSheet,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Post an item'),
            )
          : null,
    );
  }

  int _gridColumns(double width) => width >= 1120 ? 3 : width >= 760 ? 2 : 1;

  void _showReminder(BuildContext context) {
    _loadReturnReminders(context);
  }

  Future<void> _openRentalHandoffs() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RentalHandoffsScreen(
          repository: widget.repository,
          profile: widget.profile,
        ),
      ),
    );
    if (mounted) _loadMyRentals();
  }

  Future<void> _loadReturnReminders(BuildContext context) async {
    try {
      final dueDates = await widget.repository.urgentReturnDueDates();
      if (!mounted) return;
      if (dueDates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No urgent return reminders right now.')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Return reminders'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: dueDates.map((due) {
              final time = TimeOfDay.fromDateTime(due).format(context);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(due.isBefore(DateTime.now())
                    ? 'A rental is overdue. Please arrange its return.'
                    : 'A rental is due by $time.'),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Return reminders could not load. Try again.')),
      );
    }
  }

  Future<void> _setAvailability(EquipmentItem item, bool available) async {
    try {
      await widget.repository.setAvailability(item, available);
      await _loadItems(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update this listing. Try again.')),
      );
    }
  }

  Future<void> _showRentInfo(EquipmentItem item) async {
    final requested = await showDialog<bool>(
      context: context,
      builder: (context) => _RentalRequestDialog(
        item: item,
        repository: widget.repository,
        profile: widget.profile,
        demoMode: widget.demoMode,
      ),
    );
    if (requested == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.demoMode
              ? 'Preview only. Connect Supabase to send a request.'
              : 'Checkout saved as pending. No payment has been collected.'),
        ),
      );
      await _loadItems(showLoader: false);
    }
  }

  Future<void> _showPostSheet() async {
    if (!_canPost) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => const _VerificationNotice(),
      );
      return;
    }

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => PostItemSheet(repository: widget.repository),
    );
    if (created == true) await _loadItems();
  }
}

class _RoleSwitcher extends StatelessWidget {
  const _RoleSwitcher({required this.value, required this.onChanged});

  final FlexRole value;
  final ValueChanged<FlexRole?> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<FlexRole>(
            value: value,
            onChanged: onChanged,
            iconEnabledColor: FlexShareTheme.white,
            dropdownColor: FlexShareTheme.white,
            style: const TextStyle(
              color: FlexShareTheme.white,
              fontWeight: FontWeight.w600,
            ),
            selectedItemBuilder: (context) => FlexRole.values
                .map((role) => Align(
                      alignment: Alignment.center,
                      child: Text(role.label),
                    ))
                .toList(),
            items: FlexRole.values
                .map((role) => DropdownMenuItem(
                      value: role,
                      child: Text(role.label),
                    ))
                .toList(),
          ),
        ),
      );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.role, required this.name, required this.demoMode});

  final FlexRole role;
  final String? name;
  final bool demoMode;

  @override
  Widget build(BuildContext context) {
    final isLender = role == FlexRole.lender;
    final displayName = name;
    final title = switch (role) {
      FlexRole.borrower => 'Gear for your next class.',
      FlexRole.lender => 'Your gear, rented nearby.',
      FlexRole.flexRunner => 'Campus runs, made simple.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (demoMode)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: FlexShareTheme.statusPill(FlexShareTheme.amber),
            child: const Text(
              'Preview data',
              style: TextStyle(color: Color(0xFF78350F), fontWeight: FontWeight.w600),
            ),
          ),
        Text(
            displayName == null || displayName.isEmpty
              ? title
              : 'Hi, ${displayName.split(' ').first}.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 6),
        Text(
          isLender
              ? 'Share spare gear with students across PSU.'
              : role == FlexRole.borrower
                  ? 'Borrow from nearby PSU students, between classes.'
                  : 'See what is moving around campus today.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF475569),
              ),
        ),
      ],
    );
  }
}

class _CampusPlace {
  const _CampusPlace(this.name, this.latitude, this.longitude);

  final String name;
  final double latitude;
  final double longitude;

  static const all = [
    _CampusPlace('IT Building', 9.77660, 118.73320),
    _CampusPlace('Engineering Building', 9.77610, 118.73410),
    _CampusPlace('Architecture Studio', 9.77710, 118.73450),
    _CampusPlace('Nursing Building', 9.77790, 118.73320),
    _CampusPlace('CBA Building', 9.77730, 118.73510),
  ];
}

class _CampusMapCard extends StatefulWidget {
  const _CampusMapCard({
    required this.items,
    required this.selectedBuilding,
    required this.onBuildingSelected,
  });

  final List<EquipmentItem> items;
  final String? selectedBuilding;
  final ValueChanged<String> onBuildingSelected;

  @override
  State<_CampusMapCard> createState() => _CampusMapCardState();
}

class _CampusMapCardState extends State<_CampusMapCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: const Icon(Icons.map_outlined, color: FlexShareTheme.navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Around PSU', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${widget.items.length} available · Approximate building pins',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _expanded ? 'Collapse campus map' : 'Expand campus map',
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  ),
                ],
              ),
            ),
            if (_expanded)
              SizedBox(
                height: 250,
                child: FlutterMap(
                  options: const MapOptions(
                    initialCenter: LatLng(9.77684, 118.73375),
                    initialZoom: 17,
                    minZoom: 14,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.flexshare.app',
                    ),
                    MarkerLayer(
                      markers: _CampusPlace.all.map((place) {
                        final count = widget.items
                            .where((item) => item.building == place.name)
                            .length;
                        final selected = widget.selectedBuilding == place.name;
                        return Marker(
                          point: LatLng(place.latitude, place.longitude),
                          width: selected ? 112 : 44,
                          height: selected ? 60 : 44,
                          child: GestureDetector(
                            onTap: () => widget.onBuildingSelected(place.name),
                            child: _MapPin(
                              label: _shortBuilding(place.name),
                              count: count,
                              selected: selected,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const RichAttributionWidget(
                      attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label, required this.count, required this.selected});

  final String label;
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFD1FAE5) : FlexShareTheme.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? FlexShareTheme.mint : FlexShareTheme.border,
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color.fromRGBO(15, 23, 42, 0.14),
                      offset: Offset(0, 2),
                      blurRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.location_on, color: FlexShareTheme.mint),
              ),
              Positioned(
                top: -2,
                right: -3,
                child: Container(
                  width: 19,
                  height: 19,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: FlexShareTheme.mint,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: FlexShareTheme.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (selected)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: FlexShareTheme.white,
                border: Border.all(color: FlexShareTheme.border),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: FlexShareTheme.charcoal,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
}

class _BuildingFilter extends StatelessWidget {
  const _BuildingFilter({required this.selectedBuilding, required this.onSelected});

  final String? selectedBuilding;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          scrollDirection: Axis.horizontal,
          itemCount: _CampusPlace.all.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final place = _CampusPlace.all[index];
            final selected = selectedBuilding == place.name;
            return ChoiceChip(
              label: Text(_shortBuilding(place.name)),
              selected: selected,
              onSelected: (_) => onSelected(place.name),
              selectedColor: const Color(0xFFD1FAE5),
              side: BorderSide(color: selected ? FlexShareTheme.mint : FlexShareTheme.border),
            );
          },
        ),
      );
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({
    required this.item,
    required this.lenderView,
    required this.onRent,
    required this.onAvailabilityChanged,
  });

  final EquipmentItem item;
  final bool lenderView;
  final VoidCallback onRent;
  final ValueChanged<bool> onAvailabilityChanged;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 158,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ItemImage(item: item),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _Tag(
                      label: item.isAvailable ? 'Available now' : 'On loan',
                      color: item.isAvailable ? FlexShareTheme.mint : FlexShareTheme.amber,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.category}  ·  Near ${_shortBuilding(item.building)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Rate(label: 'Hourly', amount: item.hourlyRate),
                        const SizedBox(width: 18),
                        _Rate(label: 'Daily', amount: item.dailyRate),
                      ],
                    ),
                    const Spacer(),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (item.protectionFee > 0)
                          const _CompactTag(
                            icon: Icons.shield_outlined,
                            label: 'Damage protected',
                            color: FlexShareTheme.mint,
                          ),
                        if (item.ownerIsIdVerified)
                          const _CompactTag(
                            icon: Icons.verified_outlined,
                            label: 'PSU ID Verified',
                            color: FlexShareTheme.navy,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: lenderView
                          ? OutlinedButton.icon(
                              onPressed: () => onAvailabilityChanged(!item.isAvailable),
                              icon: Icon(
                                item.isAvailable
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                                size: 17,
                              ),
                              label: Text(item.isAvailable ? 'Pause listing' : 'Make available'),
                            )
                          : FilledButton.icon(
                              onPressed: item.isAvailable ? onRent : null,
                              icon: const Icon(Icons.shopping_bag_outlined, size: 17),
                              label: const Text('Rent Now'),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _ItemImage extends StatelessWidget {
  const _ItemImage({required this.item});

  final EquipmentItem item;

  @override
  Widget build(BuildContext context) {
    final image = item.imageBytes != null
        ? Image.memory(item.imageBytes!, fit: BoxFit.cover)
        : item.imageUrl != null
            ? Image.network(
                item.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            : _fallback();
    return ColoredBox(color: const Color(0xFFEFF4F8), child: image);
  }

  Widget _fallback() => const Center(
        child: Icon(Icons.inventory_2_outlined, size: 36, color: Color(0xFF64748B)),
      );
}

class _Rate extends StatelessWidget {
  const _Rate({required this.label, required this.amount});

  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            '${_formatPhp(amount)} / ${label == 'Hourly' ? 'hr' : 'day'}',
            style: FlexShareTheme.priceStyle(
              Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      );
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: FlexShareTheme.statusPill(color),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: color == FlexShareTheme.amber
                ? const Color(0xFF78350F)
                : const Color(0xFF065F46),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _CompactTag extends StatelessWidget {
  const _CompactTag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: FlexShareTheme.statusPill(color),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color == FlexShareTheme.mint
                    ? const Color(0xFF065F46)
                    : FlexShareTheme.navy,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _RentalRequestDialog extends StatefulWidget {
  const _RentalRequestDialog({
    required this.item,
    required this.repository,
    required this.profile,
    required this.demoMode,
  });

  final EquipmentItem item;
  final EquipmentRepository repository;
  final Map<String, dynamic>? profile;
  final bool demoMode;

  @override
  State<_RentalRequestDialog> createState() => _RentalRequestDialogState();
}

class _RentalRequestDialogState extends State<_RentalRequestDialog> {
  String _durationType = 'hourly';
  int _durationCount = 1;
  String _protectionTier = 'standard';
  String _paymentMethod = 'GCash';
  bool _deliveryRequested = false;
  final _classroomController = TextEditingController();
  bool _submitting = false;
  String? _error;

  bool get _isVerifiedBorrower => widget.demoMode ||
      (widget.profile?['role'] == 'borrower' &&
          widget.profile?['is_id_verified'] == true);

  double get _unitRate =>
      _durationType == 'hourly' ? widget.item.hourlyRate : widget.item.dailyRate;

  double get _baseAmount => _unitRate * _durationCount;

  double get _protectionFee => switch (_protectionTier) {
        'none' => 0,
        'plus' => widget.item.protectionFee * 2,
        _ => widget.item.protectionFee,
      };

    double get _deliveryFee =>
      _deliveryRequested ? EquipmentRepository.campusDeliveryFee : 0;

    double get _commission =>
      _baseAmount * EquipmentRepository.platformCommissionRate;

  double get _estimatedPayable =>
      _baseAmount + _protectionFee + _deliveryFee;

  @override
  void dispose() {
    _classroomController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isVerifiedBorrower) return;
    if (_deliveryRequested && _classroomController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the classroom for delivery.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.checkoutRental(
        itemId: widget.item.id,
        durationType: _durationType,
        durationCount: _durationCount,
        protectionTier: _protectionTier,
        paymentMethod: _paymentMethod,
        deliveryRequested: _deliveryRequested,
        dropoffClassroom: _deliveryRequested
            ? _classroomController.text.trim()
            : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException
            ? error.message
            : 'Could not send the request. This item may no longer be available.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Checkout'),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.sizeOf(context).height * 0.68,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.item.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                Text('Rental duration', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'hourly', label: Text('Hourly')),
                    ButtonSegment(value: 'daily', label: Text('Daily')),
                  ],
                  selected: {_durationType},
                  onSelectionChanged: (selection) => setState(() {
                    _durationType = selection.first;
                    _durationCount = 1;
                  }),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Decrease duration',
                      onPressed: _durationCount <= 1
                          ? null
                          : () => setState(() => _durationCount--),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        '$_durationCount ${_durationType == 'hourly' ? 'hour(s)' : 'day(s)'}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Increase duration',
                      onPressed: _durationCount >= (_durationType == 'hourly' ? 24 : 30)
                          ? null
                          : () => setState(() => _durationCount++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Text('Meetup or delivery', style: Theme.of(context).textTheme.labelLarge),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Self-meetup'),
                  value: false,
                  groupValue: _deliveryRequested,
                  onChanged: (value) => setState(() => _deliveryRequested = value ?? false),
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Book a FlexRunner Courier'),
                  subtitle: Text(
                    'Delivered to your classroom · ${_formatPhp(EquipmentRepository.campusDeliveryFee)}',
                  ),
                  value: true,
                  groupValue: _deliveryRequested,
                  onChanged: (value) => setState(() => _deliveryRequested = value ?? true),
                ),
                if (_deliveryRequested) ...[
                  TextFormField(
                    controller: _classroomController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Drop-off classroom',
                      hintText: 'e.g. CBA Room 204',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<String>(
                  value: _protectionTier,
                  decoration: const InputDecoration(
                    labelText: 'Damage protection',
                    prefixIcon: Icon(Icons.shield_outlined, color: FlexShareTheme.mint),
                  ),
                  items: [
                    const DropdownMenuItem(value: 'none', child: Text('No protection · ₱0')),
                    DropdownMenuItem(
                      value: 'standard',
                      child: Text('Standard · ${_formatPhp(widget.item.protectionFee)}'),
                    ),
                    DropdownMenuItem(
                      value: 'plus',
                      child: Text('Plus · ${_formatPhp(widget.item.protectionFee * 2)}'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _protectionTier = value);
                  },
                ),
                const SizedBox(height: 16),
                _CheckoutBreakdown(
                  baseAmount: _baseAmount,
                  unitRate: _unitRate,
                  durationCount: _durationCount,
                  durationType: _durationType,
                  protectionFee: _protectionFee,
                  protectionTier: _protectionTier,
                  deliveryFee: _deliveryFee,
                  commission: _commission,
                  ownerPayout: _baseAmount - _commission,
                  estimatedPayable: _estimatedPayable,
                ),
                const SizedBox(height: 16),
                Text('Pay with', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'GCash',
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('GCash'),
                    ),
                    ButtonSegment(
                      value: 'Maya',
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('Maya'),
                    ),
                  ],
                  selected: {_paymentMethod},
                  onSelectionChanged: (selection) => setState(() {
                    _paymentMethod = selection.first;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.demoMode
                      ? 'Preview only. No rental or payment record will be created.'
                      : 'Checkout requests are saved as pending. Payment is not charged until wallet-provider confirmation.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!_isVerifiedBorrower) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'PSU ID verification is required before you can rent.',
                    style: TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: _submitting || !_isVerifiedBorrower ? null : _submit,
            child: _submitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.demoMode ? 'Preview checkout' : 'Create checkout'),
          ),
        ],
      );
}

class _CheckoutBreakdown extends StatelessWidget {
  const _CheckoutBreakdown({
    required this.baseAmount,
    required this.unitRate,
    required this.durationCount,
    required this.durationType,
    required this.protectionFee,
    required this.protectionTier,
    required this.deliveryFee,
    required this.commission,
    required this.ownerPayout,
    required this.estimatedPayable,
  });

  final double baseAmount;
  final double unitRate;
  final int durationCount;
  final String durationType;
  final double protectionFee;
  final String protectionTier;
  final double deliveryFee;
  final double commission;
  final double ownerPayout;
  final double estimatedPayable;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FlexShareTheme.white,
          border: Border.all(color: FlexShareTheme.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(15, 23, 42, 0.05),
              offset: Offset(0, 4),
              blurRadius: 12,
            ),
          ],
        ),
        child: Column(
          children: [
            _BreakdownRow(
              label:
                  'Base rental (${_formatPhp(unitRate)} × $durationCount ${durationType == 'hourly' ? 'hr' : 'day'})',
              amount: baseAmount,
            ),
            const SizedBox(height: 10),
            _BreakdownRow(
              label: protectionTier == 'none'
                  ? 'Damage protection (none)'
                  : 'Damage protection (${protectionTier == 'plus' ? 'Plus' : 'Standard'})',
              amount: protectionFee,
              icon: Icons.shield_outlined,
              color: FlexShareTheme.mint,
            ),
            if (deliveryFee > 0) ...[
              const SizedBox(height: 10),
              _BreakdownRow(
                label: 'FlexRunner campus delivery',
                amount: deliveryFee,
                icon: Icons.delivery_dining_outlined,
                color: FlexShareTheme.amber,
              ),
            ],
            const SizedBox(height: 10),
            _BreakdownRow(
                label:
                  'Platform commission · ${(EquipmentRepository.platformCommissionRate * 100).toStringAsFixed(0)}% owner deduction',
              amount: -commission,
              color: FlexShareTheme.navy,
              emphasizeNegative: true,
            ),
            const Divider(height: 20),
            _BreakdownRow(
              label: 'Owner payout before handoff',
              amount: ownerPayout,
              strong: true,
            ),
            const SizedBox(height: 10),
            _BreakdownRow(
              label: 'Estimated borrower total',
              amount: estimatedPayable,
              strong: true,
              total: true,
            ),
          ],
        ),
      );
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.amount,
    this.icon,
    this.color,
    this.strong = false,
    this.total = false,
    this.emphasizeNegative = false,
  });

  final String label;
  final double amount;
  final IconData? icon;
  final Color? color;
  final bool strong;
  final bool total;
  final bool emphasizeNegative;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: total ? FlexShareTheme.navy : FlexShareTheme.charcoal,
                fontWeight: strong || total ? FontWeight.w700 : FontWeight.w400,
                fontSize: total ? 14 : 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${emphasizeNegative ? '− ' : ''}${_formatPhp(amount.abs())}',
            style: FlexShareTheme.priceStyle(
              TextStyle(
                color: color ?? FlexShareTheme.charcoal,
                fontWeight: strong || total ? FontWeight.w700 : FontWeight.w500,
                fontSize: total ? 14 : 12,
              ),
            ),
          ),
        ],
      );
}

class _ReturnReminderBanner extends StatelessWidget {
  const _ReturnReminderBanner({required this.rental, required this.onTap});

  final RentalHandoff rental;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = rental.dueTimestamp.difference(DateTime.now());
    final overdue = remaining.isNegative;
    final absolute = remaining.abs();
    final countdown = absolute.inHours > 0
        ? '${absolute.inHours}h ${absolute.inMinutes.remainder(60).toString().padLeft(2, '0')}m'
        : '${absolute.inMinutes}m';

    return Material(
      color: const Color(0xFFFEF3C7),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: FlexShareTheme.amber),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.alarm, color: Color(0xFFB45309)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  overdue
                      ? '${rental.itemTitle} is overdue by $countdown. Return it now to avoid further late fees.'
                      : '${rental.itemTitle} is due in $countdown. Return it on time to avoid late fees.',
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Color(0xFF78350F)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 38, color: const Color(0xFF64748B)),
                const SizedBox(height: 14),
                Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(detail, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                if (action != null) ...[const SizedBox(height: 12), action!],
              ],
            ),
          ),
        ),
      );
}

class _VerificationNotice extends StatelessWidget {
  const _VerificationNotice();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PSU ID verification needed', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Verified student lenders can post equipment. Your account role and ID status are managed by PSU support.',
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      );
}

class PostItemSheet extends StatefulWidget {
  const PostItemSheet({super.key, required this.repository});

  final EquipmentRepository repository;

  @override
  State<PostItemSheet> createState() => _PostItemSheetState();
}

class _PostItemSheetState extends State<PostItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _hourly = TextEditingController();
  final _daily = TextEditingController();
  final _protection = TextEditingController(text: '20');
  String _category = 'Calculator';
  String _building = _CampusPlace.all.first.name;
  XFile? _image;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _hourly.dispose();
    _daily.dispose();
    _protection.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (image != null && mounted) setState(() => _image = image);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_image == null) {
      setState(() => _error = 'Add a clear photo so classmates know what they are borrowing.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final place = _CampusPlace.all.firstWhere((entry) => entry.name == _building);
      await widget.repository.createListing(
        title: _title.text.trim(),
        category: _category,
        hourlyRate: double.parse(_hourly.text),
        dailyRate: double.parse(_daily.text),
        protectionFee: double.parse(_protection.text),
        building: _building,
        latitude: place.latitude,
        longitude: place.longitude,
        image: _image!,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException
            ? error.message
            : 'Could not post this item. Check your connection and try again.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Post an item', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Give gear in your bag another good day on campus.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _title,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Item name',
                        hintText: 'e.g. Casio fx-991EX Calculator',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: const [
                        'Calculator',
                        'Camera',
                        'Drawing Tablet',
                        'Electronics',
                        'Lab Gear',
                        'Other',
                      ]
                          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _category = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fields = [
                          _moneyField(_hourly, '₱ / hour'),
                          _moneyField(_daily, '₱ / day'),
                          _moneyField(_protection, 'Protection fee'),
                        ];
                        if (constraints.maxWidth < 480) {
                          return Column(
                            children: [
                              Row(children: [Expanded(child: fields[0]), const SizedBox(width: 10), Expanded(child: fields[1])]),
                              const SizedBox(height: 10),
                              fields[2],
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: fields[0]),
                            const SizedBox(width: 10),
                            Expanded(child: fields[1]),
                            const SizedBox(width: 10),
                            Expanded(child: fields[2]),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _building,
                      decoration: const InputDecoration(labelText: 'Meet near'),
                      items: _CampusPlace.all
                          .map((place) => DropdownMenuItem(
                                value: place.name,
                                child: Text(place.name),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _building = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickPhoto,
                      icon: Icon(_image == null ? Icons.add_a_photo_outlined : Icons.check_circle_outline),
                      label: Text(_image == null ? 'Add a photo' : 'Photo added'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.publish_outlined),
                        label: Text(_submitting ? 'Posting…' : 'Publish listing'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _moneyField(TextEditingController controller, String label) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, prefixText: '₱ '),
        validator: (value) {
          final amount = double.tryParse(value ?? '');
          return amount == null || amount < 0 ? 'Enter a valid amount' : null;
        },
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Add an item name' : null;
}

String _formatPhp(double amount) =>
    '₱${amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)}';

String _shortBuilding(String building) => switch (building) {
      'IT Building' => 'IT Bldg',
      'Engineering Building' => 'Engineering Bldg',
      'Architecture Studio' => 'Architecture Studio',
      'Nursing Building' => 'Nursing Bldg',
      'CBA Building' => 'CBA Bldg',
      _ => building,
    };