import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/domain/models/bucket.dart';
import '../notifiers/buckets_notifier.dart';

final bucketsProvider =
    AsyncNotifierProvider<BucketsNotifier, List<Bucket>>(BucketsNotifier.new);