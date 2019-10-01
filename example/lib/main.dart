import 'dart:async';

import 'package:batching_future/batching_future.dart';

class Doubler implements BatchComputer<int, int> {
  @override
  Future<List<int>> compute(List<int> batchedInputs) {
    return Future.value(batchedInputs.map((i) => i * 2).toList());
  }
}

main(List<String> args) async {
  final batcher = createBatcher(Doubler(),
      maxBatchSize: 3, maxWaitDuration: Duration(milliseconds: 500));
  final inputs = [4,6,8];
  final futures = inputs.map((i) => batcher.submit(i));
  final results = await Future.wait(futures);
  print(results);
}
