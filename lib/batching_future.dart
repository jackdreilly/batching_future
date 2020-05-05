/// Exposes [createBatcher] which batches computation requests until either
/// a max batch size or max wait duration is reached.
///
import 'dart:async';
import 'dart:collection';

import 'package:quiver/collection.dart';
import 'package:quiver/iterables.dart';
import 'package:synchronized/synchronized.dart';

/// Converts input type [K] to output type [V] for every item in
/// [batchedInputs]. There must be exactly one item in output list for every
/// item in input list, and assumes that input[i] => output[i].
typedef BatchComputer<K, V> = FutureOr<List<V>> Function(List<K> batchedInputs);

/// Interface to submit (possible) batched computation requests.
abstract class BatchingFutureProvider<K, V> {
  Future<V> submit(K inputValue);
}

/// Returns a batcher which computes transformations in batch using [computer].
/// The batcher will wait to compute until [maxWaitDuration] is reached since
/// the first item in the current batch is received, or [maxBatchSize] items
/// are in the current batch, whatever happens first.
/// If [maxBatchSize] or [maxWaitDuration] is null, then the triggering
/// condition is ignored, but at least one condition must be supplied.
///
/// Warning: If [maxWaitDuration] is not supplied, then it is possible that
/// a partial batch will never finish computing.
///
/// If [cacheSize] is specified, then the provider is backed by a cache of
/// the specified size, which immediately resolves computations, rather than
/// passing to the batching computer.
BatchingFutureProvider<K, V> createBatcher<K, V>(BatchComputer<K, V> computer,
    {int maxBatchSize, Duration maxWaitDuration, int cacheSize}) {
  if (!((maxBatchSize != null || maxWaitDuration != null) &&
      (maxWaitDuration == null || maxWaitDuration.inMilliseconds > 0) &&
      (maxBatchSize == null || maxBatchSize > 0))) {
    throw ArgumentError(
        "At least one of {maxBatchSize, maxWaitDuration} must be specified and be positive values");
  }
  final provider = _Impl<K, V>(computer, maxBatchSize, maxWaitDuration);
  if (cacheSize == null) {
    return provider;
  }
  return _CachingBatchingFuture(provider: provider, maximumSize: cacheSize);
}

// Holds the input value and the future to complete it.
class _Payload<K, V> {
  final K k;
  final Completer<V> completer;

  _Payload(this.k, this.completer);
}

enum _ExecuteCommand { EXECUTE }

/// Implements [createBatcher].
class _Impl<K, V> implements BatchingFutureProvider<K, V> {
  /// Queues computation requests.
  final controller = StreamController<dynamic>();

  /// Queues the input values with their futures to complete.
  final queue = Queue<_Payload>();

  /// Locks access to [listen] to make queue-processing single-threaded.
  final lock = Lock();

  /// [maxWaitDuration] timer, as a stored reference to cancel early if needed.
  Timer timer;

  /// Performs the input->output batch transformation.
  final BatchComputer<K, V> computer;

  /// See [createBatcher].
  final int maxBatchSize;

  /// See [createBatcher].
  final Duration maxWaitDuration;
  _Impl(this.computer, this.maxBatchSize, this.maxWaitDuration) {
    controller.stream.listen(listen);
  }

  void dispose() {
    controller.close();
  }

  @override
  Future<V> submit(K inputValue) {
    final completer = Completer<V>();
    controller.add(_Payload(inputValue, completer));
    return completer.future;
  }

  // Synchronous event-processing logic.
  void listen(dynamic event) async {
    await lock.synchronized(() {
      if (event.runtimeType == _ExecuteCommand) {
        if (timer?.isActive ?? true) {
          // The timer got reset, so ignore this old request.
          // The current timer needs to inactive and non-null
          // for the execution to be legitimate.
          return;
        }
        execute();
      } else {
        addPayload(event as _Payload);
      }
      return;
    });
  }

  void addPayload(_Payload _payload) {
    if (queue.isEmpty && maxWaitDuration != null) {
      // This is the first item of the batch.
      // Trigger the timer so we are guaranteed to start computing
      // this batch before [maxWaitDuration].
      timer = Timer(maxWaitDuration, triggerTimer);
    }
    queue.add(_payload);
    if (maxBatchSize != null && queue.length >= maxBatchSize) {
      execute();
      return;
    }
  }

  void execute() async {
    timer?.cancel();
    if (queue.isEmpty) {
      return;
    }
    final results = await computer(List<K>.of(queue.map((p) => p.k)));
    for (var pair in zip<Object>([queue, results])) {
      (pair[0] as _Payload).completer.complete(pair[1] as V);
    }
    queue.clear();
  }

  void triggerTimer() {
    listen(_ExecuteCommand.EXECUTE);
  }
}

/// A BatchingFutureProvider backed by a cache.
///
/// Requests are either immediately satisfied when a cache hit succeeds,
/// or proxied through the child [provider] otherwise.
class _CachingBatchingFuture<K, V> implements BatchingFutureProvider<K, V> {
  final LruMap<K, V> _cache;
  final BatchingFutureProvider<K, V> _provider;

  _CachingBatchingFuture(
      {BatchingFutureProvider<K, V> provider, int maximumSize = 200})
      : _cache = LruMap(maximumSize: maximumSize),
        _provider = provider;
  @override
  Future<V> submit(K inputValue) async {
    if (_cache.containsKey(inputValue)) {
      return Future.value(_cache[inputValue]);
    }
    final result = await _provider.submit(inputValue);
    _cache[inputValue] = result;
    return result;
  }
}
