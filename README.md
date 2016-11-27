# ReactiveObjCBridge

After announced Swift, ReactiveCocoa was rewritten in Swift. This framework
creates a bridge between those Swift and Objective-C APIs ([ReactiveSwift][]
and [ReactiveObjC][]).

Because the APIs are based on fundamentally different designs, the conversion is
not always one-to-one; however, every attempt has been made to faithfully
translate the concepts between the two APIs (and languages).

The bridged types include:

 1. [`RACSignal` and `SignalProducer` or `Signal`](#racsignal-and-signalproducer-or-signal)
 1. [`RACCommand` and `Action`](#raccommand-and-action)
 1. [`RACScheduler` and `SchedulerType`](#racscheduler-and-schedulertype)
 1. [`RACDisposable` and `Disposable`](#racdisposable-and-disposable)

For the complete bridging API, including documentation, see [`ObjectiveCBridging.swift`][ObjectiveCBridging].

## `RACSignal` and `SignalProducer` or `Signal`

In ReactiveSwift, “cold” signals are represented by the `SignalProducer` type,
and “hot” signals are represented by the `Signal` type.

“Cold” `RACSignal`s can be converted into `SignalProducer`s using the
`bridgedSignalProducer()` free function:

```swift
func bridgedSignalProducer<T>(from signal: RACSignal<T>) -> SignalProducer<T?, NSError>
```

“Hot” `RACSignal`s cannot be directly converted into `Signal`s, because _any_
`RACSignal` subscription could potentially involve side effects. To obtain a
`Signal`, use `RACSignal.toSignalProducer` followed by `SignalProducer.start`,
which will make those potential side effects explicit.

For the other direction, use the `toRACSignal()` instance method.

When invoked on a `SignalProducer`, these functions will create a `RACSignal` to
 `start()` the producer once for each subscription:

```swift
extension SignalProducerProtocol where Value: AnyObject {
    func toRACSignal() -> RACSignal<Value>
}

extension SignalProducerProtocol where Value: OptionalProtocol, Value.Wrapped: AnyObject {
	func toRACSignal() -> RACSignal<Value.Wrapped>
}

```

When inoked on a `Signal`, these methods will create a `RACSignal` that simply
observes it:

```swift
extension SignalProtocol where Value: AnyObject {
    func toRACSignal() -> RACSignal<Value.Wrapped> {
}

extension SignalProtocol where Value: OptionalProtocol, Value.Wrapped: AnyObject {
    func toRACSignal() -> RACSignal<Value.Wrapped> {
}
```

## `RACCommand` and `Action`

To convert `RACCommand`s into the new `Action` type, use the `bridgedAction()`
free function:

```swift
func bridgedAction<I, O>(from command: RACCommand<I, O>) -> Action<I?, O?, NSError>
```

To convert `Action`s into `RACCommand`s, use the `toRACCommand()` instance
method:

```swift
extension ActionProtocol where Input: AnyObject, Output: AnyObject {
	func toRACCommand() -> RACCommand<Input, Output>
}

extension ActionProtocol where Input: OptionalProtocol, Input.Wrapped: AnyObject, Output: AnyObject {
	func toRACCommand() -> RACCommand<Input.Wrapped, Output>
}

extension ActionProtocol where Input: AnyObject, Output: OptionalProtocol, Output.Wrapped: AnyObject {
	func toRACCommand() -> RACCommand<Input, Output.Wrapped>
}

extension ActionProtocol where Input: OptionalProtocol, Input.Wrapped: AnyObject, Output: OptionalProtocol, Output.Wrapped: AnyObject {
	func toRACCommand() -> RACCommand<Input.Wrapped, Output.Wrapped>
}
```

**NOTE:** The `executing` properties of actions and commands are not
synchronized across the API bridge. To ensure consistency, only observe the
`executing` property from the base object (the one passed _into_ the bridge, not
retrieved from it), so updates occur no matter which object is used for
execution.

## `RACScheduler` and `SchedulerType`

Any `RACScheduler` instance is automatically a `DateSchedulerType` (and
therefore a `SchedulerType`), and can be passed directly into any function or
method that expects one.

Some (but not all) `SchedulerType`s from RAC 3 can be converted into
`RACScheduler` instances, using the `toRACScheduler()` method:

```swift
extension ImmediateScheduler {
	func toRACScheduler() -> RACScheduler
}

extension UIScheduler {
	func toRACScheduler() -> RACScheduler
}

extension QueueScheduler {
	func toRACScheduler() -> RACScheduler
}
```

## `RACDisposable` and `Disposable`

Any `RACDisposable` instance is automatically a `Disposable`, and can be used
 directly anywhere a type conforming to `Disposable` is expected.

Although there is no direct conversion from `Disposable` into `RACDisposable`,
it is easy to do manually:

```swift
let swiftDisposable: Disposable
let objcDisposable = RACDisposable {
    swiftDisposable.dispose()
}
```

[ReactiveSwift]: https://github.com/ReactiveCocoa/ReactiveSwift/
[ReactiveObjC]: https://github.com/ReactiveCocoa/ReactiveObjC/
[ObjectiveCBridging]: ReactiveObjCBridge/ObjectiveCBridging.swift
