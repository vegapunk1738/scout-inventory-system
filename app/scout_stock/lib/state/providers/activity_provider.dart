import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notifiers/activity_notifier.dart';

final activityProvider =
    NotifierProvider<ActivityNotifier, ActivityState>(ActivityNotifier.new);