import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notifiers/me_notifier.dart';

final meProvider = NotifierProvider<MeNotifier, MeState>(MeNotifier.new);