# Actor machines

`Actor` owns one generated machine value. It serializes access to that value
and exposes the same typed initial state, actions, and transitions as direct
machine execution.

```swift
let actor = try Counter.Actor()
let transition = try await actor.send(.advance)
let state = await actor.state
let advanceIsEnabled = try await actor.isEnabled(.advance)

assert(state == transition.after)
assert(advanceIsEnabled)
```

SwiftUI stores the generated machine value directly in `@State`. Use `Actor`
when asynchronous work must serialize access to the same machine.

```swift
let actor = try Counter.Actor(.init(count: 4))
let state = await actor.state
assert(state.count == 4)
```
