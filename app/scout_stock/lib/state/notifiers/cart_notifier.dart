import 'dart:math';

import 'package:riverpod/riverpod.dart';
import '../../domain/models/item.dart';

class RemovedCartEntry {
  const RemovedCartEntry({required this.item, required this.index});

  final Item item;
  final int index;
}

class CartState {
  const CartState({
    required this.items,
    required this.undoStack,
    this.checkingOut = false,
  });

  final List<Item> items;
  final List<RemovedCartEntry> undoStack;
  final bool checkingOut;

  bool get canUndo => undoStack.isNotEmpty;
  int get undoCount => undoStack.length;
  bool get isEmpty => items.isEmpty;

  CartState copyWith({
    List<Item>? items,
    List<RemovedCartEntry>? undoStack,
    bool? checkingOut,
  }) {
    return CartState(
      items: items ?? this.items,
      undoStack: undoStack ?? this.undoStack,
      checkingOut: checkingOut ?? this.checkingOut,
    );
  }
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() {
    return const CartState(items: [], undoStack: []);
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

  /// Checkout — will be wired to the backend transactions API later.
  /// For now, clears the cart and returns a local txn ID.
  Future<({bool ok, String? txnId, String? error})> checkout() async {
    if (state.checkingOut) return (ok: false, txnId: null, error: 'busy');
    if (state.items.isEmpty) return (ok: false, txnId: null, error: 'empty');

    state = state.copyWith(checkingOut: true);

    try {
      // TODO: Replace with real API call via transactionsProvider
      await Future.delayed(const Duration(milliseconds: 500));

      final txnId = '#TXN-${Random().nextInt(90000) + 10000}';
      state = const CartState(items: [], undoStack: []);
      return (ok: true, txnId: txnId, error: null);
    } catch (e) {
      return (ok: false, txnId: null, error: '$e');
    } finally {
      state = state.copyWith(checkingOut: false);
    }
  }
}