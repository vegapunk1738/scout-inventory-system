class Item {
  const Item({
    required this.id,
    required this.name,
    required this.bucketId,
    required this.bucketBarcode,
    required this.bucketName,
    required this.quantity,
    required this.maxQuantity,
    required this.emoji,
  });

  /// The item_type UUID from the backend.
  final String id;

  final String name;

  /// The bucket UUID — used in API requests (checkout/return).
  final String bucketId;

  /// The bucket barcode (e.g. "SSB-TNT-912") — used for display only.
  final String bucketBarcode;

  final String bucketName;

  final int quantity;
  final int maxQuantity;

  final String emoji;

  Item copyWith({
    String? id,
    String? name,
    String? bucketId,
    String? bucketBarcode,
    String? bucketName,
    int? quantity,
    int? maxQuantity,
    String? emoji,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      bucketId: bucketId ?? this.bucketId,
      bucketBarcode: bucketBarcode ?? this.bucketBarcode,
      bucketName: bucketName ?? this.bucketName,
      quantity: quantity ?? this.quantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      emoji: emoji ?? this.emoji,
    );
  }

  static String formatBucketId({
    required String bucketCode3,
    required int sequence,
  }) =>
      'SSB-$bucketCode3-${sequence.toString().padLeft(3, '0')}';

  static String formatItemId({
    required String itemCode3,
    required int sequence,
  }) =>
      'SSI-$itemCode3-${sequence.toString().padLeft(3, '0')}';
}