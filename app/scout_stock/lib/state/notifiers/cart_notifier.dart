import 'package:riverpod/riverpod.dart';
import '../../domain/models/item.dart';

class RemovedCartEntry {
  const RemovedCartEntry({required this.item, required this.index});

  final Item item;
  final int index;
}

class CartState {
  const CartState({required this.items, required this.undoStack});

  final List<Item> items;
  final List<RemovedCartEntry> undoStack;

  bool get canUndo => undoStack.isNotEmpty;
  int get undoCount => undoStack.length;

  CartState copyWith({List<Item>? items, List<RemovedCartEntry>? undoStack}) {
    return CartState(
      items: items ?? this.items,
      undoStack: undoStack ?? this.undoStack,
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    // Demo seed (remove later when Scan/Bucket flow is wired)
    final demoItems = <Item>[
      Item(
        id: Item.formatItemId(itemCode3: 'CPT', sequence: 1),
        name: 'Coleman 4-Person Tent',
        bucketId: Item.formatBucketId(bucketCode3: 'TSB', sequence: 1),
        bucketName: 'Tents Bucket',
        quantity: 1,
        maxQuantity: 4,
        emoji: '🏕️',
      ),
      Item(
        id: Item.formatItemId(itemCode3: 'HDS', sequence: 2),
        name: 'Heavy Duty Stakes',
        bucketId: Item.formatBucketId(bucketCode3: 'STB', sequence: 2),
        bucketName: 'Stakes Bucket',
        quantity: 4,
        maxQuantity: 8,
        emoji: '📌',
      ),
      Item(
        id: Item.formatItemId(itemCode3: 'PSB', sequence: 3),
        name: 'Propane Stove (2 Burner)',
        bucketId: Item.formatBucketId(bucketCode3: 'SVB', sequence: 3),
        bucketName: 'Stoves Bucket',
        quantity: 1,
        maxQuantity: 4,
        emoji: '🔥',
      ),
      Item(
        id: Item.formatItemId(itemCode3: 'MKS', sequence: 4),
        name: 'Mess Kit (Full Set)',
        bucketId: Item.formatBucketId(bucketCode3: 'MKB', sequence: 4),
        bucketName: 'Mess Kits Bucket',
        quantity: 4,
        maxQuantity: 4,
        emoji: '🍲',
      ),
    ];

    return CartState(items: demoItems, undoStack: const []);
  }

  void addItem(Item item) {
    final items = state.items;
    final idx = items.indexWhere((x) => x.id == item.id);

    if (idx == -1) {
      final q = item.quantity.clamp(1, item.maxQuantity);
      state = state.copyWith(
        items: [
          ...items,
          item.copyWith(quantity: q),
        ],
      );
      return;
    }

    final current = items[idx];
    final nextQty = (current.quantity + item.quantity).clamp(
      1,
      current.maxQuantity,
    );

    final updated = [...items];
    updated[idx] = current.copyWith(quantity: nextQty);
    state = state.copyWith(items: updated);
  }

  void increment(String itemId) {
    final items = state.items;
    final idx = items.indexWhere((x) => x.id == itemId);
    if (idx == -1) return;

    final item = items[idx];
    if (item.quantity >= item.maxQuantity) return;

    final updated = [...items];
    updated[idx] = item.copyWith(quantity: item.quantity + 1);
    state = state.copyWith(items: updated);
  }

  void decrement(String itemId) {
    final items = state.items;
    final idx = items.indexWhere((x) => x.id == itemId);
    if (idx == -1) return;

    final item = items[idx];
    if (item.quantity <= 1) return;

    final updated = [...items];
    updated[idx] = item.copyWith(quantity: item.quantity - 1);
    state = state.copyWith(items: updated);
  }

  void remove(String itemId) {
    final items = state.items;
    final idx = items.indexWhere((x) => x.id == itemId);
    if (idx == -1) return;

    final removed = items[idx];

    final updatedItems = [...items]..removeAt(idx);
    final updatedUndo = [
      ...state.undoStack,
      RemovedCartEntry(item: removed, index: idx),
    ];

    state = state.copyWith(items: updatedItems, undoStack: updatedUndo);
  }

  void undoRemove() {
    if (state.undoStack.isEmpty) return;

    final undo = [...state.undoStack];
    final entry = undo.removeLast();

    final items = [...state.items];

    // If it already exists (same id), restore its snapshot (quantity, etc.)
    final existingIdx = items.indexWhere((x) => x.id == entry.item.id);
    if (existingIdx != -1) {
      items[existingIdx] = entry.item.copyWith(
        quantity: entry.item.quantity.clamp(1, entry.item.maxQuantity),
      );
    } else {
      final insertAt = entry.index.clamp(0, items.length);
      items.insert(
        insertAt,
        entry.item.copyWith(
          quantity: entry.item.quantity.clamp(1, entry.item.maxQuantity),
        ),
      );
    }

    state = state.copyWith(items: items, undoStack: undo);
  }

  void clear() {
    state = const CartState(items: [], undoStack: []);
  }

  void bump(String itemId, int delta) {
    final items = state.items;
    final idx = items.indexWhere((x) => x.id == itemId);
    if (idx == -1) return;

    final it = items[idx];
    final nextQty = (it.quantity + delta).clamp(1, it.maxQuantity);

    if (nextQty == it.quantity) return;

    final nextItems = [...items];
    nextItems[idx] = it.copyWith(quantity: nextQty);

    state = state.copyWith(items: nextItems);
  }
}
