//
//  ObjectiveCBridging.swift
//  ReactiveObjCBridge
//
//  Created by Justin Spahr-Summers on 2014-07-02.
//  Copyright (c) 2014 GitHub, Inc. All rights reserved.
//

import Foundation
import ReactiveObjC
import ReactiveSwift
import Result

extension SignalProtocol {
	/// Turns each value into an Optional.
	fileprivate func optionalize() -> Signal<Value?, Error> {
		return map(Optional.init)
	}
}

extension SignalProducerProtocol {
	/// Turns each value into an Optional.
	fileprivate func optionalize() -> SignalProducer<Value?, Error> {
		return lift { $0.optionalize() }
	}
}

extension RACDisposable: Disposable {}
extension RACScheduler: DateScheduler {
	/// The current date, as determined by this scheduler.
	public var currentDate: Date {
		return Date()
	}

	/// Schedule an action for immediate execution.
	///
	/// - note: This method calls the Objective-C implementation of `schedule:`
	///         method.
	///
	/// - parameters:
	///   - action: Closure to perform.
	///
	/// - returns: Disposable that can be used to cancel the work before it
	///            begins.
	@discardableResult
	public func schedule(_ action: @escaping () -> Void) -> Disposable? {
		let disposable: RACDisposable? = self.schedule(action) // Call the Objective-C implementation
		return disposable as Disposable?
	}

	/// Schedule an action for execution at or after the given date.
	///
	/// - parameters:
	///   - date: Starting date.
	///   - action: Closure to perform.
	///
	/// - returns: Optional disposable that can be used to cancel the work
	///            before it begins.
	@discardableResult
	public func schedule(after date: Date, action: @escaping () -> Void) -> Disposable? {
		return self.after(date, schedule: action)
	}

	/// Schedule a recurring action at the given interval, beginning at the
	/// given start time.
	///
	/// - parameters:
	///   - date: Starting date.
	///   - repeatingEvery: Repetition interval.
	///   - withLeeway: Some delta for repetition.
	///   - action: Closure of the action to perform.
	///
	/// - returns: Optional `Disposable` that can be used to cancel the work
	///            before it begins.
	@discardableResult
	public func schedule(after date: Date, interval: DispatchTimeInterval, leeway: DispatchTimeInterval, action: @escaping () -> Void) -> Disposable? {
		return self.after(date, repeatingEvery: interval.timeInterval, withLeeway: leeway.timeInterval, schedule: action)
	}
}

extension ImmediateScheduler {
	/// Create `RACScheduler` that performs actions instantly.
	///
	/// - returns: `RACScheduler` that instantly performs actions.
	public func toRACScheduler() -> RACScheduler {
		return RACScheduler.immediate()
	}
}

extension UIScheduler {
	/// Create `RACScheduler` for `UIScheduler`
	///
	/// - returns: `RACScheduler` instance that queues events on main thread.
	public func toRACScheduler() -> RACScheduler {
		return RACScheduler.mainThread()
	}
}

extension QueueScheduler {
	/// Create `RACScheduler` backed with own queue
	///
	/// - returns: Instance `RACScheduler` that queues events on
	///            `QueueScheduler`'s queue.
	public func toRACScheduler() -> RACScheduler {
		return RACTargetQueueScheduler(name: "org.reactivecocoa.ReactiveObjCBridge.QueueScheduler.toRACScheduler()", targetQueue: queue)
	}
}

private func defaultNSError(_ message: String, file: String, line: Int) -> NSError {
	return Result<(), NSError>.error(message, file: file, line: line)
}

/// Create a `SignalProducer` which will subscribe to the provided signal once
/// for each invocation of `start()`.
///
/// - parameters:
///   - signal: The signal to bridge to a signal producer.
///   - file: Current file name.
///   - line: Current line in file.
///
/// - returns: Signal producer created from the provided signal.
public func bridgedSignalProducer<Value>(from signal: RACSignal<Value>, file: String = #file, line: Int = #line) -> SignalProducer<Value?, AnyError> {
	return SignalProducer<Value?, AnyError> { observer, disposable in
		let next: (_ value: Value?) -> Void = { obj in
			observer.send(value: obj)
		}

		let failed: (_ error: Swift.Error?) -> () = { error in
			observer.send(error: AnyError(error ?? defaultNSError("Nil RACSignal error", file: file, line: line)))
		}

		let completed = {
			observer.sendCompleted()
		}

		disposable += signal.subscribeNext(next, error: failed, completed: completed)
	}
}

extension SignalProducerProtocol where Value: AnyObject {
	/// Create a `RACSignal` that will `start()` the producer once for each
	/// subscription.
	///
	/// - note: Any `interrupted` events will be silently discarded.
	///
	/// - returns: `RACSignal` instantiated from `self`.
	public func toRACSignal() -> RACSignal<Value> {
		return RACSignal<Value>.createSignal { subscriber in
			let selfDisposable = self.start { event in
				switch event {
				case let .value(value):
					subscriber.sendNext(value)
				case let .failed(error):
					subscriber.sendError(error)
				case .completed:
					subscriber.sendCompleted()
				case .interrupted:
					break
				}
			}

			return RACDisposable {
				selfDisposable.dispose()
			}
		}
	}
}

extension SignalProducerProtocol where Value: OptionalProtocol, Value.Wrapped: AnyObject {
	/// Create a `RACSignal` that will `start()` the producer once for each
	/// subscription.
	///
	/// - note: Any `interrupted` events will be silently discarded.
	/// - note: This overload is necessary to prevent `Optional.none` from
	///         being bridged to `NSNull` (instead of `nil`).
	///         See ReactiveObjCBridge#5 for more details.
	///
	/// - returns: `RACSignal` instantiated from `self`.
	public func toRACSignal() -> RACSignal<Value.Wrapped> {
		return RACSignal<Value.Wrapped>.createSignal { subscriber in
			let selfDisposable = self.start { event in
				switch event {
				case let .value(value):
					subscriber.sendNext(value.optional)
				case let .failed(error):
					subscriber.sendError(error)
				case .completed:
					subscriber.sendCompleted()
				case .interrupted:
					break
				}
			}
			
			return RACDisposable {
				selfDisposable.dispose()
			}
		}
	}
}

extension SignalProtocol where Value: AnyObject {
	/// Create a `RACSignal` that will observe the given signal.
	///
	/// - note: Any `interrupted` events will be silently discarded.
	///
	/// - returns: `RACSignal` instantiated from `self`.
	public func toRACSignal() -> RACSignal<Value> {
		return RACSignal<Value>.createSignal { subscriber in
			let selfDisposable = self.observe { event in
				switch event {
				case let .value(value):
					subscriber.sendNext(value)
				case let .failed(error):
					subscriber.sendError(error)
				case .completed:
					subscriber.sendCompleted()
				case .interrupted:
					break
				}
			}

			return RACDisposable {
				selfDisposable?.dispose()
			}
		}
	}
}

extension SignalProtocol where Value: OptionalProtocol, Value.Wrapped: AnyObject {
	/// Create a `RACSignal` that will observe the given signal.
	///
	/// - note: Any `interrupted` events will be silently discarded.
	/// - note: This overload is necessary to prevent `Optional.none` from 
	///         being bridged to `NSNull` (instead of `nil`).
	///         See ReactiveObjCBridge#5 for more details.
	///
	/// - returns: `RACSignal` instantiated from `self`.
	public func toRACSignal() -> RACSignal<Value.Wrapped> {
		return RACSignal<Value.Wrapped>.createSignal { subscriber in
			let selfDisposable = self.observe { event in
				switch event {
				case let .value(value):
					subscriber.sendNext(value.optional)
				case let .failed(error):
					subscriber.sendError(error)
				case .completed:
					subscriber.sendCompleted()
				case .interrupted:
					break
				}
			}
			
			return RACDisposable {
				selfDisposable?.dispose()
			}
		}
	}
}

// MARK: -

extension ActionProtocol {
	fileprivate var isCommandEnabled: RACSignal<NSNumber> {
		return self.isEnabled.producer
			.map { $0 as NSNumber }
			.toRACSignal()
	}
}

/// Creates an Action that will execute the receiver.
///
/// - note: The returned Action will not necessarily be marked as executing
///         when the command is. However, the reverse is always true: the
///         RACCommand will always be marked as executing when the action
///         is.
///
/// - parameters:
///   - file: Current file name.
///   - line: Current line in file.
///
/// - returns: Action created from `self`.
public func bridgedAction<Input, Output>(from command: RACCommand<Input, Output>, file: String = #file, line: Int = #line) -> Action<Input?, Output?, AnyError> {
	let enabledProperty = MutableProperty(true)

	enabledProperty <~ bridgedSignalProducer(from: command.enabled)
		.map { $0 as! Bool }
		.flatMapError { _ in SignalProducer<Bool, NoError>(value: false) }

	return Action<Input?, Output?, AnyError>(enabledIf: enabledProperty) { input -> SignalProducer<Output?, AnyError> in
		let signal: RACSignal<Output> = command.execute(input)

		return bridgedSignalProducer(from: signal)
	}
}

extension ActionProtocol where Input: AnyObject, Output: AnyObject {
	/// Creates a RACCommand that will execute the action.
	///
	/// - note: The returned command will not necessarily be marked as executing
	///         when the action is. However, the reverse is always true: the Action
	///         will always be marked as executing when the RACCommand is.
	///
	/// - returns: `RACCommand` with bound action.
	public func toRACCommand() -> RACCommand<Input, Output> {
		return RACCommand<Input, Output>(enabled: action.isCommandEnabled) { input -> RACSignal<Output> in
			return self.apply(input!)
				.toRACSignal()
		}
	}
}

extension ActionProtocol where Input: OptionalProtocol, Input.Wrapped: AnyObject, Output: AnyObject {
	/// Creates a RACCommand that will execute the action.
	///
	/// - note: The returned command will not necessarily be marked as executing
	///         when the action is. However, the reverse is always true: the Action
	///         will always be marked as executing when the RACCommand is.
	///
	/// - returns: `RACCommand` with bound action.
	public func toRACCommand() -> RACCommand<Input.Wrapped, Output> {
		return RACCommand<Input.Wrapped, Output>(enabled: action.isCommandEnabled) { input -> RACSignal<Output> in
			return self
				.apply(Input(reconstructing: input))
				.toRACSignal()
		}
	}
}

extension ActionProtocol where Input: AnyObject, Output: OptionalProtocol, Output.Wrapped: AnyObject {
	/// Creates a RACCommand that will execute the action.
	///
	/// - note: The returned command will not necessarily be marked as executing
	///         when the action is. However, the reverse is always true: the Action
	///         will always be marked as executing when the RACCommand is.
	///
	/// - returns: `RACCommand` with bound action.
	public func toRACCommand() -> RACCommand<Input, Output.Wrapped> {
		return RACCommand<Input, Output.Wrapped>(enabled: action.isCommandEnabled) { input -> RACSignal<Output.Wrapped> in
			return self
				.apply(input!)
				.toRACSignal()
		}
	}
}

extension ActionProtocol where Input: OptionalProtocol, Input.Wrapped: AnyObject, Output: OptionalProtocol, Output.Wrapped: AnyObject {
	/// Creates a RACCommand that will execute the action.
	///
	/// - note: The returned command will not necessarily be marked as executing
	///         when the action is. However, the reverse is always true: the Action
	///         will always be marked as executing when the RACCommand is.
	///
	/// - returns: `RACCommand` with bound action.
	public func toRACCommand() -> RACCommand<Input.Wrapped, Output.Wrapped> {
		return RACCommand<Input.Wrapped, Output.Wrapped>(enabled: action.isCommandEnabled) { input -> RACSignal<Output.Wrapped> in
			return self
				.apply(Input(reconstructing: input))
				.toRACSignal()
		}
	}
}

// MARK: - Helpers

extension DispatchTimeInterval {
	fileprivate var timeInterval: TimeInterval {
		switch self {
		case let .seconds(s):
			return TimeInterval(s)
		case let .milliseconds(ms):
			return TimeInterval(TimeInterval(ms) / 1000.0)
		case let .microseconds(us):
			return TimeInterval(UInt64(us) * NSEC_PER_USEC) / TimeInterval(NSEC_PER_SEC)
		case let .nanoseconds(ns):
			return TimeInterval(ns) / TimeInterval(NSEC_PER_SEC)
		}
	}
}
