import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:scout_stock/domain/models/managed_user.dart';
import 'package:scout_stock/state/notifiers/users_notifier.dart';

/// Single source of truth for the admin users list.
///
/// Lazy: does not fetch until the first widget watches it.
final usersProvider =
    AsyncNotifierProvider<UsersNotifier, List<ManagedUser>>(UsersNotifier.new);