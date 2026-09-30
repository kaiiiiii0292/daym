import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EquipmentItem {
  const EquipmentItem({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.category,
    required this.hourlyRate,
    required this.dailyRate,
    required this.protectionFee,
    required this.building,
    required this.latitude,
    required this.longitude,
    required this.imageUrl,
    required this.ownerName,
    required this.ownerDepartment,
    required this.ownerIsIdVerified,
    this.imageBytes,
    this.isAvailable = true,
  });

  final String id;
  final String ownerId;
  final String title;
  final String category;
  final double hourlyRate;
  final double dailyRate;
  final double protectionFee;
  final String building;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final String ownerName;
  final String ownerDepartment;
  final bool ownerIsIdVerified;
  final Uint8List? imageBytes;
  final bool isAvailable;

  EquipmentItem copyWith({bool? isAvailable}) => EquipmentItem(
        id: id,
        ownerId: ownerId,
        title: title,
        category: category,
        hourlyRate: hourlyRate,
        dailyRate: dailyRate,
        protectionFee: protectionFee,
        building: building,
        latitude: latitude,
        longitude: longitude,
        imageUrl: imageUrl,
        ownerName: ownerName,
        ownerDepartment: ownerDepartment,
        ownerIsIdVerified: ownerIsIdVerified,
        imageBytes: imageBytes,
        isAvailable: isAvailable ?? this.isAvailable,
      );

  factory EquipmentItem.fromMap(Map<String, dynamic> row) => EquipmentItem(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String,
        title: row['title'] as String,
        category: row['category'] as String,
        hourlyRate: (row['hourly_rate_php'] as num).toDouble(),
        dailyRate: (row['daily_rate_php'] as num).toDouble(),
        protectionFee: (row['protection_fee_php'] as num).toDouble(),
        building: row['campus_building'] as String,
        latitude: (row['lat'] as num).toDouble(),
        longitude: (row['lng'] as num).toDouble(),
        imageUrl: row['image_url'] as String?,
        ownerName: row['owner_name'] as String? ?? 'PSU student',
        ownerDepartment: row['owner_department'] as String? ?? '',
        ownerIsIdVerified: row['owner_is_id_verified'] as bool? ?? false,
        isAvailable: row['is_available'] as bool? ?? true,
      );
}

class RentalHandoff {
  const RentalHandoff({
    required this.rentalId,
    required this.itemTitle,
    required this.borrowerId,
    required this.ownerId,
    required this.dueTimestamp,
    required this.durationType,
    required this.durationCount,
    required this.status,
    required this.paymentStatus,
    required this.pickupVerifiedAt,
    required this.returnVerifiedAt,
  });

  final String rentalId;
  final String itemTitle;
  final String borrowerId;
  final String ownerId;
  final DateTime dueTimestamp;
  final String durationType;
  final int durationCount;
  final String status;
  final String paymentStatus;
  final DateTime? pickupVerifiedAt;
  final DateTime? returnVerifiedAt;

  factory RentalHandoff.fromMap(Map<String, dynamic> row) => RentalHandoff(
        rentalId: row['rental_id'] as String,
        itemTitle: row['item_title'] as String,
        borrowerId: row['borrower_id'] as String,
        ownerId: row['owner_id'] as String,
        dueTimestamp: DateTime.parse(row['due_timestamp'] as String).toLocal(),
        durationType: row['duration_type'] as String,
        durationCount: (row['duration_count'] as num).toInt(),
        status: row['rental_status'] as String,
        paymentStatus: row['payment_status'] as String,
        pickupVerifiedAt: row['pickup_verified_at'] == null
            ? null
            : DateTime.parse(row['pickup_verified_at'] as String).toLocal(),
        returnVerifiedAt: row['return_verified_at'] == null
            ? null
            : DateTime.parse(row['return_verified_at'] as String).toLocal(),
      );
}

class DeliveryJob {
  const DeliveryJob({
    required this.id,
    required this.rentalId,
    required this.itemTitle,
    required this.pickupBuilding,
    required this.dropoffClassroom,
    required this.deliveryFee,
    required this.platformCut,
    required this.status,
    required this.createdAt,
    required this.pickupVerifiedAt,
  });

  final String id;
  final String rentalId;
  final String itemTitle;
  final String pickupBuilding;
  final String dropoffClassroom;
  final double deliveryFee;
  final double platformCut;
  final String status;
  final DateTime createdAt;
  final DateTime? pickupVerifiedAt;

  double get payout => deliveryFee - platformCut;

  factory DeliveryJob.fromMap(Map<String, dynamic> row) => DeliveryJob(
        id: row['delivery_id'] as String,
        rentalId: row['rental_id'] as String,
        itemTitle: row['item_title'] as String,
        pickupBuilding: row['pickup_building'] as String,
        dropoffClassroom: row['dropoff_classroom'] as String,
        deliveryFee: (row['delivery_fee'] as num).toDouble(),
        platformCut: (row['platform_cut'] as num).toDouble(),
        status: row['delivery_status'] as String,
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        pickupVerifiedAt: row['pickup_verified_at'] == null
          ? null
          : DateTime.parse(row['pickup_verified_at'] as String).toLocal(),
      );
}

class EquipmentRepository {
  EquipmentRepository(this.client);

  static const platformCommissionRate = 0.12;
  static const campusDeliveryFee = 80.0;

  final SupabaseClient? client;
  final List<EquipmentItem> _demoItems = List.of(_sampleItems);
  RealtimeChannel? _listingChannel;
  RealtimeChannel? _deliveryChannel;

  bool get isDemo => client == null;

  void watchListingChanges(void Function() onChange) {
    if (client == null || _listingChannel != null) return;
    _listingChannel = client!
        .channel('flexshare-equipment-feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'equipment_items',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> stopWatchingListingChanges() async {
    final channel = _listingChannel;
    _listingChannel = null;
    if (client != null && channel != null) await client!.removeChannel(channel);
  }

  Future<void> stopWatchingDeliveryChanges() async {
    final channel = _deliveryChannel;
    _deliveryChannel = null;
    if (client != null && channel != null) await client!.removeChannel(channel);
  }

  void watchDeliveryChanges(void Function() onChange) {
    if (client == null || _deliveryChannel != null) return;
    _deliveryChannel = client!
        .channel('flexshare-delivery-board')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'flexrunner_deliveries',
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  static const _sampleItems = <EquipmentItem>[
    EquipmentItem(
      id: 'demo-calculator',
      ownerId: 'demo-it',
      title: 'Casio fx-991EX Calculator',
      category: 'Calculator',
      hourlyRate: 8,
      dailyRate: 80,
      protectionFee: 20,
      building: 'IT Building',
      latitude: 9.77660,
      longitude: 118.73320,
      imageUrl:
          'https://images.unsplash.com/photo-1587145820266-a5951ee6f620?w=800&q=85&fit=crop',
      ownerName: 'Mika Reyes',
      ownerDepartment: 'IT',
      ownerIsIdVerified: false,
    ),
    EquipmentItem(
      id: 'demo-camera',
      ownerId: 'demo-business',
      title: 'Canon EOS DSLR Camera',
      category: 'Camera',
      hourlyRate: 150,
      dailyRate: 800,
      protectionFee: 200,
      building: 'CBA Building',
      latitude: 9.77730,
      longitude: 118.73510,
      imageUrl:
          'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=800&q=85&fit=crop',
      ownerName: 'Ari Lim',
      ownerDepartment: 'Business',
      ownerIsIdVerified: false,
    ),
    EquipmentItem(
      id: 'demo-tablet',
      ownerId: 'demo-architecture',
      title: 'Wacom Drawing Tablet',
      category: 'Drawing Tablet',
      hourlyRate: 30,
      dailyRate: 180,
      protectionFee: 50,
      building: 'Architecture Studio',
      latitude: 9.77710,
      longitude: 118.73450,
      imageUrl:
          'https://images.unsplash.com/photo-1585790050230-5dd28404ccb9?w=800&q=85&fit=crop',
      ownerName: 'Leah Dizon',
      ownerDepartment: 'Architecture',
      ownerIsIdVerified: false,
    ),
    EquipmentItem(
      id: 'demo-arduino',
      ownerId: 'demo-engineering',
      title: 'Arduino Uno Kit',
      category: 'Electronics',
      hourlyRate: 20,
      dailyRate: 120,
      protectionFee: 40,
      building: 'Engineering Building',
      latitude: 9.77610,
      longitude: 118.73410,
      imageUrl:
          'https://images.unsplash.com/photo-1553406830-ef2513450d76?w=800&q=85&fit=crop',
      ownerName: 'Noah Santos',
      ownerDepartment: 'Engineering',
      ownerIsIdVerified: false,
    ),
    EquipmentItem(
      id: 'demo-nursing',
      ownerId: 'demo-nursing',
      title: 'Nursing Lab Gear',
      category: 'Lab Gear',
      hourlyRate: 25,
      dailyRate: 160,
      protectionFee: 50,
      building: 'Nursing Building',
      latitude: 9.77790,
      longitude: 118.73320,
      imageUrl:
          'https://images.unsplash.com/photo-1584982751601-97dcc096659c?w=800&q=85&fit=crop',
      ownerName: 'Gab Cruz',
      ownerDepartment: 'Nursing',
      ownerIsIdVerified: false,
    ),
  ];

  Future<List<EquipmentItem>> availableItems() async {
    if (client == null) return List.unmodifiable(_demoItems);

    final rows = await client!
        .from('equipment_marketplace')
        .select()
        .order('title');
    return rows.map(EquipmentItem.fromMap).toList();
  }

  Future<List<EquipmentItem>> myListings() async {
    if (client == null) return List.unmodifiable(_demoItems);
    final profile = await currentProfile();
    if (profile == null) return const [];

    final rows = await client!
        .from('equipment_items')
        .select()
        .eq('owner_id', profile['id'])
        .order('created_at', ascending: false);
    return rows
        .map((row) => EquipmentItem.fromMap({
              ...row,
              'owner_name': profile['full_name'],
              'owner_department': profile['department'],
              'owner_is_id_verified': profile['is_id_verified'],
            }))
        .toList();
  }

  Future<void> setAvailability(EquipmentItem item, bool available) async {
    if (client == null) {
      final index = _demoItems.indexWhere((entry) => entry.id == item.id);
      if (index >= 0) _demoItems[index] = item.copyWith(isAvailable: available);
      return;
    }
    await client!
        .from('equipment_items')
        .update({'is_available': available})
        .eq('id', item.id);
  }

  Future<void> checkoutRental({
    required String itemId,
    required String durationType,
    required int durationCount,
    required String protectionTier,
    required String paymentMethod,
    required bool deliveryRequested,
    String? dropoffClassroom,
  }) async {
    if (client == null) {
      final index = _demoItems.indexWhere((item) => item.id == itemId);
      if (index >= 0) {
        _demoItems[index] = _demoItems[index].copyWith(isAvailable: false);
      }
      return;
    }
    final profile = await currentProfile();
    if (profile == null ||
        profile['role'] != 'borrower' ||
        profile['is_id_verified'] != true) {
      throw const FormatException('A verified borrower profile is required to rent.');
    }
    await client!.rpc(
      'checkout_equipment_rental',
      params: {
        'p_item_id': itemId,
        'p_duration_type': durationType,
        'p_duration_count': durationCount,
        'p_protection_tier': protectionTier,
        'p_payment_method': paymentMethod,
        'p_delivery_requested': deliveryRequested,
        'p_dropoff_classroom': dropoffClassroom,
      },
    );
  }

  Future<List<DateTime>> urgentReturnDueDates() async {
    if (client == null) return const [];
    final profile = await currentProfile();
    if (profile == null) return const [];

    final rows = await client!
        .from('rentals')
        .select('due_timestamp')
        .eq('borrower_id', profile['id'])
        .eq('status', 'active')
        .lte(
          'due_timestamp',
          DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String(),
        )
        .order('due_timestamp');
    return rows
        .map((row) => DateTime.parse(row['due_timestamp'] as String).toLocal())
        .toList();
  }

  Future<List<RentalHandoff>> myRentalHandoffs() async {
    if (client == null) return const [];
    final rows = await client!.rpc('list_my_rental_handoffs') as List<dynamic>;
    return rows
        .map((row) => RentalHandoff.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> getRentalHandoffQr(String rentalId) async {
    if (client == null) throw StateError('QR handoffs need a Supabase connection.');
    final rows = await client!.rpc(
      'get_rental_handoff_qr',
      params: {'p_rental_id': rentalId},
    ) as List<dynamic>;
    if (rows.isEmpty) throw StateError('No QR code is available for this handoff.');
    return Map<String, dynamic>.from(rows.first as Map);
  }

  Future<String> uploadHandoffPhoto({
    required String rentalId,
    required String phase,
    required XFile image,
  }) async {
    if (client == null) throw StateError('Photo handoffs need a Supabase connection.');
    final userId = client!.auth.currentUser?.id;
    if (userId == null) throw StateError('Sign in before capturing a handoff.');
    final extension = image.name.split('.').last.toLowerCase();
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path =
        '$userId/$rentalId/${phase}_${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client!.storage.from('flexshare-handoff-photos').uploadBinary(
          path,
          await image.readAsBytes(),
          fileOptions: FileOptions(contentType: mimeType),
        );
    return path;
  }

  Future<DateTime> verifyRentalHandoff({
    required String rentalId,
    required String token,
    required String phase,
    required String photoPath,
  }) async {
    if (client == null) throw StateError('QR handoffs need a Supabase connection.');
    final result = await client!.rpc(
      'verify_rental_handoff',
      params: {
        'p_rental_id': rentalId,
        'p_qr_token': token,
        'p_phase': phase,
        'p_photo_path': photoPath,
      },
    );
    return DateTime.parse(result as String).toLocal();
  }

  Future<List<DeliveryJob>> flexrunnerDeliveries() async {
    if (client == null) return const [];
    final rows = await client!.rpc('list_my_flexrunner_deliveries') as List<dynamic>;
    return rows
        .map((row) => DeliveryJob.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> acceptDelivery(String deliveryId) async {
    if (client == null) throw StateError('Dispatch needs a Supabase connection.');
    await client!.rpc(
      'accept_flexrunner_delivery',
      params: {'p_delivery_id': deliveryId},
    );
  }

  Future<void> updateDeliveryStatus(String deliveryId, String status) async {
    if (client == null) throw StateError('Dispatch needs a Supabase connection.');
    await client!.rpc(
      'update_flexrunner_delivery_status',
      params: {'p_delivery_id': deliveryId, 'p_status': status},
    );
  }

  Future<Map<String, dynamic>?> currentProfile() async {
    final authUser = client?.auth.currentUser;
    if (client == null || authUser == null) return null;

    final existing = await client!
        .from('users')
        .select()
        .eq('auth_user_id', authUser.id)
        .maybeSingle();
    if (existing != null) return existing;

    final metadata = authUser.userMetadata ?? const <String, dynamic>{};
    final fullName = metadata['full_name'] as String?;
    final studentId = metadata['student_id_number'] as String?;
    final department = metadata['department'] as String?;
    if (fullName == null || studentId == null || department == null) return null;

    return client!
        .from('users')
        .insert({
          'auth_user_id': authUser.id,
          'full_name': fullName,
          'student_id_number': studentId,
          'department': department,
          'role': 'borrower',
          'is_id_verified': false,
          'wallet_balance': 0,
        })
        .select()
        .single();
  }

  Future<EquipmentItem> createListing({
    required String title,
    required String category,
    required double hourlyRate,
    required double dailyRate,
    required double protectionFee,
    required String building,
    required double latitude,
    required double longitude,
    required XFile image,
  }) async {
    if (client == null) {
      final item = EquipmentItem(
        id: 'demo-${DateTime.now().microsecondsSinceEpoch}',
        ownerId: 'demo-user',
        title: title,
        category: category,
        hourlyRate: hourlyRate,
        dailyRate: dailyRate,
        protectionFee: protectionFee,
        building: building,
        latitude: latitude,
        longitude: longitude,
        imageUrl: null,
        ownerName: 'You',
        ownerDepartment: 'PSU',
        ownerIsIdVerified: false,
        imageBytes: await image.readAsBytes(),
      );
      _demoItems.insert(0, item);
      return item;
    }

    final profile = await currentProfile();
    if (profile == null ||
        profile['role'] != 'lender' ||
        profile['is_id_verified'] != true) {
      throw const FormatException(
        'Only verified PSU lenders can publish listings.',
      );
    }

    final authUser = client!.auth.currentUser!;
    final extension = image.name.split('.').last.toLowerCase();
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final path = '${authUser.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client!.storage.from('flexshare-equipment').uploadBinary(
          path,
          await image.readAsBytes(),
          fileOptions: FileOptions(contentType: mimeType),
        );
    final imageUrl = client!.storage.from('flexshare-equipment').getPublicUrl(path);

    final row = await client!
        .from('equipment_items')
        .insert({
          'owner_id': profile['id'],
          'title': title,
          'category': category,
          'hourly_rate_php': hourlyRate,
          'daily_rate_php': dailyRate,
          'protection_fee_php': protectionFee,
          'campus_building': building,
          'lat': latitude,
          'lng': longitude,
          'image_url': imageUrl,
          'is_available': true,
        })
        .select()
        .single();

    return EquipmentItem.fromMap({
      ...row,
      'owner_name': profile['full_name'],
      'owner_department': profile['department'],
      'owner_is_id_verified': profile['is_id_verified'],
    });
  }
}