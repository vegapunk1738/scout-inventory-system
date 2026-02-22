import 'dart:math';
import 'package:riverpod/riverpod.dart';
import '../../domain/models/item.dart';

enum MeFilterMode { all, borrowedOnly, returnedOnly }

class BorrowedRecord {
  const BorrowedRecord({
    required this.id,
    required this.checkedOutAt,
    required this.item,
  });

  final String id;
  final DateTime checkedOutAt;
  final Item item;

  BorrowedRecord copyWith({DateTime? checkedOutAt, Item? item}) =>
      BorrowedRecord(
        id: id,
        checkedOutAt: checkedOutAt ?? this.checkedOutAt,
        item: item ?? this.item,
      );
}

class ReturnedRecord {
  const ReturnedRecord({
    required this.id,
    required this.returnedAt,
    required this.item,
  });

  final String id;
  final DateTime returnedAt;
  final Item item;
}

class MeState {
  const MeState({
    required this.mode,
    required this.submitting,
    required this.borrowed,
    required this.returned,
  });

  final MeFilterMode mode;
  final bool submitting;
  final List<BorrowedRecord> borrowed;
  final List<ReturnedRecord> returned;

  int get totalToReturn =>
      borrowed.fold<int>(0, (sum, r) => sum + r.item.quantity);

  bool get hasAny => borrowed.isNotEmpty || returned.isNotEmpty;

  MeState copyWith({
    MeFilterMode? mode,
    bool? submitting,
    List<BorrowedRecord>? borrowed,
    List<ReturnedRecord>? returned,
  }) {
    return MeState(
      mode: mode ?? this.mode,
      submitting: submitting ?? this.submitting,
      borrowed: borrowed ?? this.borrowed,
      returned: returned ?? this.returned,
    );
  }
}

class MeNotifier extends Notifier<MeState> {
  @override
  MeState build() {
    final now = DateTime.now();

    DateTime d(int daysAgo) {
      final base = DateTime(now.year, now.month, now.day);
      return base.subtract(Duration(days: daysAgo));
    }

    final borrowed = <BorrowedRecord>[
      BorrowedRecord(
        id: 'br_1',
        checkedOutAt: d(0),
        item: Item(
          id: Item.formatItemId(itemCode3: 'ULT', sequence: 1),
          name: 'Ultralight Tent',
          bucketId: Item.formatBucketId(bucketCode3: 'TSB', sequence: 1),
          bucketName: 'Tents',
          quantity: 0,
          maxQuantity: 1,
          emoji: '🏕️',
        ),
      ),
      BorrowedRecord(
        id: 'br_2',
        checkedOutAt: d(0),
        item: Item(
          id: Item.formatItemId(itemCode3: 'PEG', sequence: 2),
          name: 'Alloy Tent Pegs',
          bucketId: Item.formatBucketId(bucketCode3: 'STB', sequence: 1),
          bucketName: 'Stakes',
          quantity: 0,
          maxQuantity: 10,
          emoji: '📌',
        ),
      ),
      BorrowedRecord(
        id: 'br_3',
        checkedOutAt: d(1),
        item: Item(
          id: Item.formatItemId(itemCode3: 'SKL', sequence: 3),
          name: 'Cast Iron Skillet',
          bucketId: Item.formatBucketId(bucketCode3: 'CKB', sequence: 1),
          bucketName: 'Cooking',
          quantity: 0,
          maxQuantity: 1,
          emoji: '🍳',
        ),
      ),
    ];

    final returned = <ReturnedRecord>[
      ReturnedRecord(
        id: 'rr_1',
        returnedAt: d(6),
        item: Item(
          id: Item.formatItemId(itemCode3: 'OSP', sequence: 10),
          name: 'Osprey Pack 65L',
          bucketId: Item.formatBucketId(bucketCode3: 'PKB', sequence: 1),
          bucketName: 'Packs',
          quantity: 1,
          maxQuantity: 1,
          emoji: '🎒',
        ),
      ),
    ];

    return MeState(
      mode: MeFilterMode.all,
      submitting: false,
      borrowed: borrowed,
      returned: returned,
    );
  }

  void toggleMode(MeFilterMode tapped) {
    final next = (state.mode == tapped) ? MeFilterMode.all : tapped;
    state = state.copyWith(mode: next);
  }

  void setToReturn(String borrowedRecordId, int next) {
    final borrowed = state.borrowed;
    final idx = borrowed.indexWhere((r) => r.id == borrowedRecordId);
    if (idx == -1) return;

    final r = borrowed[idx];
    final clamped = next.clamp(0, r.item.maxQuantity);
    if (clamped == r.item.quantity) return;

    final updated = [...borrowed];
    updated[idx] = r.copyWith(item: r.item.copyWith(quantity: clamped));
    state = state.copyWith(borrowed: updated);
  }

  Future<({bool ok, String? txnId, String? error})> submitReturn() async {
    if (state.submitting) return (ok: false, txnId: null, error: 'busy');
    if (state.totalToReturn == 0) {
      return (ok: false, txnId: null, error: 'empty');
    }

    state = state.copyWith(submitting: true);
    try {
      await Future.delayed(const Duration(milliseconds: 650));
      final ok = Random().nextBool();

      if (!ok) {
        return (ok: false, txnId: null, error: 'E-RTN-500');
      }

      final now = DateTime.now();

      final newReturned = <ReturnedRecord>[];
      final newBorrowed = <BorrowedRecord>[];

      for (final br in state.borrowed) {
        final selected = br.item.quantity;
        final outQty = br.item.maxQuantity;

        if (selected <= 0) {
          newBorrowed.add(br);
          continue;
        }

        newReturned.add(
          ReturnedRecord(
            id: 'rr_${now.microsecondsSinceEpoch}_${br.id}',
            returnedAt: now,
            item: br.item.copyWith(quantity: selected, maxQuantity: selected),
          ),
        );

        final remaining = outQty - selected;
        if (remaining > 0) {
          newBorrowed.add(
            br.copyWith(
              item: br.item.copyWith(quantity: 0, maxQuantity: remaining),
            ),
          );
        }
      }

      state = state.copyWith(
        borrowed: newBorrowed,
        returned: [...newReturned, ...state.returned],
      );

      return (
        ok: true,
        txnId: '#RTN-${Random().nextInt(90000) + 10000}',
        error: null,
      );
    } finally {
      state = state.copyWith(submitting: false);
    }
  }
}
