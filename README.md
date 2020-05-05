# batching_future

Consider the case where requests against a particular API may be issued from many parts of your app asynchronously. Additionally, all these API requests could be more efficiently fetched if done in batch (as well as the API supporting batch requests).

Wouldn't it be nice if you could automatically bundle all these requests into batches with a minimal API? Welcome to `batching_future`!.

# Example

## Define your batch computation (unique to your problem)

```dart

import 'package:batching_future/batching_future.dart';

/// You define exactly how your batch computation is done here.
/// In this case, we send a single API to the Maps API to get the travel time to
/// many locations.
Future<List<Duration>> batchTravelTimes(List<DirectionsRequest> allRequests) async {
    return MapsApi.travelTimesBatch(allRequests);
}
```

## Create the batcher based on your computer

```dart

import 'package:batching_future/batching_future.dart';

/// Create the batcher!
final directionsBatcher = createBatcher(
    batchTravelTimes,
    cacheSize: 200,
    maxBatchSize: 20,
    maxWaitDuration: Duration(milliseconds: 200),
);
```

## Issue requests against the batcher

And get the result as a simple `Future`!

```dart
final DirectionsRequest request = createYourRequest();
final Duration duration = await directionsBatcher.submit(request);
```

The `duration` future will complete either when:

1. There's a cache hit, at which point, it will return immediately.
2. When the `maxWaitDuration` is reached, and your batch computation then finishes.
3. When the batch "queue" reaches length `maxBatchSize`, and your batch computation then finishes.
