# Actor machines

`Actor` owns one generated machine value. It serializes access to that value
and exposes the same typed state and actions as direct machine execution.

```swift
let actor = try Counter.Actor()
let transition = try await actor.send(.advance)

assert(await actor.state == transition.after)
assert(try await actor.isEnabled(.advance))
```

SwiftUI stores the generated machine value directly in `@State`. Use `Actor`
when asynchronous work must serialize access to the machine.
