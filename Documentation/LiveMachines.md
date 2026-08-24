# Live Machines

`Live` is an actor around one generated machine value. It serializes access to
that value and exposes the same typed state and actions. It has no separate
runtime state.

```swift
let live = try Counter.Live()
let transition = try await live.send(.advance)

assert(await live.state == transition.after)
assert(try await live.isEnabled(.advance))
```

`@TLAActor` is the same adapter shape for application actors. SwiftUI needs no
adapter: its `@State` stores the generated machine value directly.

```swift
let actor = try CounterHost.Actor()
let transition = try await actor.send(.advance)
assert(await actor.state == transition.after)
```
