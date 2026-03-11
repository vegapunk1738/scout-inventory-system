import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notifiers/transactions_notifier.dart';

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, MyTransactionsState>(
  TransactionsNotifier.new,
);