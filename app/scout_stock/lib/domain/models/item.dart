class Item {
  const Item({
    required this.id,
    required this.name,
    required this.bucketId,
    required this.bucketName,
    required this.quantity,
    required this.maxQuantity,
    required this.emoji,
  });

  /// Example: "SSI-PTI-001"
  final String id;

  final String name;

  /// Example: "SSB-TSB-001"
  final String bucketId;

  final String bucketName;

  final int quantity;
  final int maxQuantity;

  final String emoji;

  Item copyWith({
    String? id,
    String? name,
    String? bucketId,
    String? bucketName,
    int? quantity,
    int? maxQuantity,
    String? emoji,
  }) {
    return Item(
      id: id ?? this.id,
      name: name ?? this.name,
      bucketId: bucketId ?? this.bucketId,
      bucketName: bucketName ?? this.bucketName,
      quantity: quantity ?? this.quantity,
      maxQuantity: maxQuantity ?? this.maxQuantity,
      emoji: emoji ?? this.emoji,
    );
  }

  /// Helpers for the ID convention you described.
  /// You choose the 3-letter code (e.g. TSB, PTI) and the sequence (001, 002...).
  static String formatBucketId({
    required String bucketCode3,
    required int sequence,
  }) => 'SSB-$bucketCode3-${sequence.toString().padLeft(3, '0')}';

  static String formatItemId({
    required String itemCode3,
    required int sequence,
  }) => 'SSI-$itemCode3-${sequence.toString().padLeft(3, '0')}';
}
