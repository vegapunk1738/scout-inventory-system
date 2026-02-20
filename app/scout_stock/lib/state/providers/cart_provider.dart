import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notifiers/cart_notifier.dart';

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
