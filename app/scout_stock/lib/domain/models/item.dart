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

  final String id;

  final String name;

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

  static String formatBucketId({
    required String bucketCode3,
    required int sequence,
  }) => 'SSB-$bucketCode3-${sequence.toString().padLeft(3, '0')}';

  static String formatItemId({
    required String itemCode3,
    required int sequence,
  }) => 'SSI-$itemCode3-${sequence.toString().padLeft(3, '0')}';
}
