import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/data/api/api_client.dart';
import 'package:scout_stock/domain/models/item.dart';
import 'package:scout_stock/state/providers/transactions_provider.dart';

// ─── State ──────────────────────────────────────────────────────────────────

class _UndoEntry {
  const _UndoEntry({required this.item, required this.index});
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
  final List<_UndoEntry> undoStack;
  final bool checkingOut;

  bool get isEmpty => items.isEmpty;
  int get totalCount => items.fold<int>(0, (s, it) => s + it.quantity);
  int get undoCount => undoStack.length;
  bool get canUndo => undoStack.isNotEmpty;

  CartState copyWith({
    List<Item>? items,
    List<_UndoEntry>? undoStack,
    bool? checkingOut,
  }) {
    return CartState(
      items: items ?? this.items,
      undoStack: undoStack ?? this.undoStack,
      checkingOut: checkingOut ?? this.checkingOut,
    );
  }
}

// ─── Notifier ───────────────────────────────────────────────────────────────

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState(items: [], undoStack: []);

  void addItem(Item item) {
    final items = [...state.items];
    final idx = items.indexWhere((x) => x.id == item.id);

    if (idx != -1) {
      // Already in cart — update quantity (clamped to maxQuantity)
      items[idx] = item.copyWith(
        quantity: item.quantity.clamp(1, item.maxQuantity),
      );
    } else {
      items.add(
        item.copyWith(quantity: item.quantity.clamp(1, item.maxQuantity)),
      );
    }

    state = state.copyWith(items: items);
  }

  void remove(String itemId) {
    final items = [...state.items];
    final idx = items.indexWhere((x) => x.id == itemId);
    if (idx == -1) return;

    final removed = items.removeAt(idx);
    final undo = [...state.undoStack, _UndoEntry(item: removed, index: idx)];

    state = state.copyWith(items: items, undoStack: undo);
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

  /// Checkout via the real backend transactions API.
  ///
  /// Uses [TransactionsNotifier.checkout] which sends the cart items
  /// with proper bucket_id (UUID) and item_type_id to the backend.
  ///
  /// Returns a record with:
  /// - `ok`: whether checkout succeeded
  /// - `txnId`: the backend transaction ID on success
  /// - `error`: human-readable error message on failure
  Future<({bool ok, String? txnId, String? error, List<Item> items})> checkout() async {
    if (state.checkingOut) return (ok: false, txnId: null, error: 'busy', items: const <Item>[]);
    if (state.items.isEmpty) return (ok: false, txnId: null, error: 'empty', items: const <Item>[]);

    // Snapshot items before clearing — needed for the success dialog.
    final checkedOutItems = List<Item>.unmodifiable(state.items);

    state = state.copyWith(checkingOut: true);

    try {
      final txNotifier = ref.read(transactionsProvider.notifier);
      final txnId = await txNotifier.checkout(state.items);

      // Clear cart on success
      state = const CartState(items: [], undoStack: []);
      return (ok: true, txnId: txnId, error: null, items: checkedOutItems);
    } on ApiException catch (e) {
      String errorMsg;

      if (e.isConflict) {
        // 409 — overborrowing or race condition
        errorMsg = e.message;
      } else if (e.isNotFound) {
        // 404 — bucket or item deleted while in cart
        errorMsg = 'Some items are no longer available. '
            'Please clear your cart and scan again.';
      } else if (e.isUnauthorized) {
        errorMsg = 'Session expired. Please log in again.';
      } else {
        errorMsg = e.displayMessage;
      }

      return (ok: false, txnId: null, error: errorMsg, items: const <Item>[]);
    } catch (e) {
      return (ok: false, txnId: null, error: '$e', items: const <Item>[]);
    } finally {
      state = state.copyWith(checkingOut: false);
    }
  }
}