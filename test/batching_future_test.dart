import 'package:batching_future/batching_future.dart';
import 'package:test/test.dart';

Future<List<int>> timesTwo(List<int> inputs) async =>
    inputs.map((i) => i * 2).toList();

void main() {
  test('Should trigger after timeout', () async {
    final maxDuration = Duration(milliseconds: 200);
    final batchSize = 3;
    final doubler = createBatcher(timesTwo,
        maxWaitDuration: maxDuration, maxBatchSize: batchSize);
    final start = DateTime.now();
    final eightF = doubler.submit(4);
    final tenF = doubler.submit(5);
    final eight = await eightF;
    final finish = DateTime.now();
    final ten = await tenF;
    final finishTen = DateTime.now();
    final duration = finish.difference(start);
    final durationTen = finishTen.difference(finish);
    expect(eight, equals(8));
    expect(ten, equals(10));
    expect(duration.inMilliseconds, inInclusiveRange(190, 250));
    expect(durationTen.inMilliseconds, lessThan(10));
  });
  test('Should compute many batches', () async {
    final maxDuration = Duration(milliseconds: 200);
    final batchSize = 3;
    final doubler = createBatcher(timesTwo,
        maxWaitDuration: maxDuration, maxBatchSize: batchSize);
    final start = DateTime.now();
    final results =
        await Future.wait(Iterable.generate(10).map((i) => doubler.submit(i)));
    final duration = DateTime.now().difference(start);
    expect(results, equals(Iterable.generate(10).map((i) => i * 2).toList()));
    expect(duration.inMilliseconds, inInclusiveRange(190, 250));
  });
  test('Should compute many batches no wait', () async {
    final maxDuration = Duration(milliseconds: 200);
    final batchSize = 3;
    final doubler = createBatcher(timesTwo,
        maxWaitDuration: maxDuration, maxBatchSize: batchSize);
    final start = DateTime.now();
    final results =
        await Future.wait(Iterable.generate(12).map((i) => doubler.submit(i)));
    final duration = DateTime.now().difference(start);
    expect(results, equals(Iterable.generate(12).map((i) => i * 2).toList()));
    expect(duration.inMilliseconds, lessThan(100));
  });
  test('Batch should never compute', () async {
    final batchSize = 3;
    final doubler = createBatcher(timesTwo, maxBatchSize: batchSize);
    final futures = Iterable.generate(2).map((i) => doubler
        .submit(i)
        .timeout(Duration(milliseconds: 100), onTimeout: () => -1));
    final results = await Future.wait(futures);
    for (var result in results) {
      expect(result, equals(-1));
    }
  });
  test('Batch computes without timeout', () async {
    final batchSize = 3;
    final doubler = createBatcher(timesTwo, maxBatchSize: batchSize);
    final futures = Iterable.generate(3).map((i) => doubler
        .submit(i)
        .timeout(Duration(milliseconds: 100), onTimeout: () => -1));
    final results = await Future.wait(futures);
    expect(results, equals(Iterable.generate(3).map((i) => i * 2).toList()));
  });
  test('Batch computes without maxBatch', () async {
    final maxDuration = Duration(milliseconds: 50);
    final doubler = createBatcher(timesTwo, maxWaitDuration: maxDuration);
    final futures = Iterable.generate(3).map((i) => doubler.submit(i));
    final results = await Future.wait(futures);
    expect(results, equals(Iterable.generate(3).map((i) => i * 2).toList()));
  });
  test('Check asserts', () {
    expect(() => createBatcher(timesTwo), throwsArgumentError);
    expect(
        () => createBatcher(timesTwo,
            maxWaitDuration: Duration(milliseconds: -1)),
        throwsArgumentError);
    expect(() => createBatcher(timesTwo, maxBatchSize: 0), throwsArgumentError);
  });
}
