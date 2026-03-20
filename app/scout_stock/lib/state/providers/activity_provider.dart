import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scout_stock/state/notifiers/activity_notifier.dart';


final activityProvider =
    NotifierProvider<ActivityNotifier, ActivityState>(ActivityNotifier.new);