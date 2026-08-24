# Live Machines

`Live` is an actor that owns one generated machine value. It serializes access
to that value and exposes the same typed state and actions.

```swift
let live = try Counter.Live()
let transition = try await live.send(.advance)

assert(await live.state == transition.after)
assert(try await live.isEnabled(.advance))
```

`@TLAActor` is the same adapter shape for application actors. It owns its
generated machine value.

```swift
let actor = try CounterHost.Actor()
let transition = try await actor.send(.advance)
assert(await actor.state == transition.after)
```
