import 'dart:async';

import 'package:batching_future/batching_future.dart';

main(List<String> args) async {
  final batcher = createBatcher<int, int>((i) => i.map((i) => i * 2).toList(),
      maxBatchSize: 3, maxWaitDuration: Duration(milliseconds: 500));
  final inputs = [4, 6, 8];
  final futures = inputs.map((i) => batcher.submit(i));
  final results = await Future.wait(futures);
  print(results);
}
