//
//  ObjectiveCBridgingSpec.swift
//  ReactiveObjCBridge
//
//  Created by Justin Spahr-Summers on 2015-01-23.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

import ReactiveObjC
import ReactiveObjCBridge
import ReactiveSwift
import Result
import Nimble
import Quick
import XCTest

class ObjectiveCBridgingSpec: QuickSpec {
	override func spec() {
		describe("RACScheduler") {
			var originalScheduler: RACTestScheduler!
			var scheduler: DateScheduler!

			beforeEach {
				originalScheduler = RACTestScheduler()
				scheduler = originalScheduler as DateScheduler
			}

			it("gives current date") {
				let expected = Date()
				let actual = scheduler.currentDate
				expect(actual.timeIntervalSinceReferenceDate).to(beCloseTo(expected.timeIntervalSinceReferenceDate, within: 0.0003))
			}

			it("schedules actions") {
				var actionRan: Bool = false

				scheduler.schedule {
					actionRan = true
				}

				expect(actionRan) == false
				originalScheduler.step()
				expect(actionRan) == true
			}

			it("does not invoke action if disposed") {
				var actionRan: Bool = false

				let disposable: Disposable? = scheduler.schedule {
					actionRan = true
				}

				expect(actionRan) == false
				disposable!.dispose()
				originalScheduler.step()
				expect(actionRan) == false
			}
		}

		describe("signalProducer") {
			it("should subscribe once per start()") {
				var subscriptions = 0

				let racSignal = RACSignal<NSNumber>.createSignal { subscriber in
					subscriber.sendNext(subscriptions)
					subscriber.sendCompleted()

					subscriptions += 1

					return nil
				}

				let producer = bridgedSignalProducer(from: racSignal).map { $0 as! Int }

				expect((producer.single())?.value) == 0
				expect((producer.single())?.value) == 1
				expect((producer.single())?.value) == 2
			}

			it("should forward errors") {
				let error = TestError.default

				let racSignal = RACSignal<AnyObject>.error(error)
				let producer = bridgedSignalProducer(from: racSignal)
				let result = producer.last()

				expect(result?.error) == AnyError(error)
			}
		}

		describe("toRACSignal") {
			let key = NSLocalizedDescriptionKey
			let userInfo: [String: String] = [key: "TestValue"]
			let testNSError = NSError(domain: "TestDomain", code: 1, userInfo: userInfo)
			describe("on a Signal") {
				it("should forward events") {
					let (signal, observer) = Signal<NSNumber, NoError>.pipe()
					let racSignal = signal.toRACSignal()

					var lastValue: NSNumber?
					var didComplete = false

					racSignal.subscribeNext({ number in
						lastValue = number
					}, completed: {
						didComplete = true
					})

					expect(lastValue).to(beNil())

					for number in [1, 2, 3] {
						observer.send(value: number as NSNumber)
						expect(lastValue) == number as NSNumber
					}

					expect(didComplete) == false
					observer.sendCompleted()
					expect(didComplete) == true
				}

				it("should convert errors to NSError") {
					let (signal, observer) = Signal<AnyObject, TestError>.pipe()
					let racSignal = signal.toRACSignal()

					let expectedError = TestError.error2
					var error: TestError?

					racSignal.subscribeError {
						error = $0 as? TestError
						return
					}

					observer.send(error: expectedError)
					expect(error) == expectedError
				}

				it("should maintain userInfo on NSError") {
					let (signal, observer) = Signal<AnyObject, NSError>.pipe()
					let racSignal = signal.toRACSignal()

					var error: String?

					racSignal.subscribeError {
						error = $0?.localizedDescription
						return
					}

					observer.send(error: testNSError)

					expect(error) == userInfo[key]
				}

				it("should bridge next events with value Optional<Any>.none to nil in Objective-C") {
					let (signal, observer) = Signal<Optional<AnyObject>, NSError>.pipe()
					let racSignal = signal.toRACSignal().replay().materialize()

					observer.send(value: nil)
					observer.sendCompleted()

					let event = racSignal.first()
					expect(event?.value).to(beNil())
				}
			}

			describe("on a SignalProducer") {
				it("should start once per subscription") {
					var subscriptions = 0

					let producer = SignalProducer { () -> Result<NSNumber, NoError> in
						defer {
							subscriptions += 1
						}

						return .success(subscriptions as NSNumber)
					}
					let racSignal = producer.toRACSignal()

					expect(racSignal.first()) == 0
					expect(racSignal.first()) == 1
					expect(racSignal.first()) == 2
				}

				it("should convert errors to NSError") {
					let producer = SignalProducer<AnyObject, TestError>(error: .error1)
					let racSignal = producer.toRACSignal().materialize()

					let event = racSignal.first()
					expect(event?.error as? NSError) == TestError.error1 as NSError
				}

				it("should maintain userInfo on NSError") {
					let producer = SignalProducer<AnyObject, NSError>(error: testNSError)
					let racSignal = producer.toRACSignal().materialize()

					let event = racSignal.first()
					let userInfoValue = event?.error?.localizedDescription
					expect(userInfoValue) == userInfo[key]
				}

				it("should bridge next events with value Optional<AnyObject>.none to nil in Objective-C") {
					let producer = SignalProducer<Optional<AnyObject>, NSError>(value: nil)
					let racSignal = producer.toRACSignal().materialize()

					let event = racSignal.first()
					expect(event?.value).to(beNil())
				}
			}
		}

		describe("toAction") {
			var command: RACCommand<NSNumber, NSNumber>!
			var results: [Int] = []

			var enabledSubject: RACSubject<NSNumber>!
			var enabled = false

			var action: Action<NSNumber?, NSNumber?, AnyError>!

			beforeEach {
				enabledSubject = RACSubject()
				results = []

				let enabledSignal = RACSignal<NSNumber>.createSignal { subscriber in
					return enabledSubject.subscribe(subscriber)
				}

				command = RACCommand<NSNumber, NSNumber>(enabled: enabledSignal) { input in
					let inputNumber = input as! Int + 1
					return RACSignal<NSNumber>.`return`(inputNumber as NSNumber)
				}

				expect(command).notTo(beNil())

				command.enabled.subscribeNext { enabled = $0 as! Bool }
				expect(enabled) == true

				let values = bridgedSignalProducer(from: command.executionSignals)
					.map { bridgedSignalProducer(from: $0!) }
					.flatten(.concat)

				values.startWithResult { results.append($0.value as! Int) }
				expect(results) == []

				action = bridgedAction(from: command)
			}

			it("should reflect the enabledness of the command") {
				expect(action.isEnabled.value) == true

				enabledSubject.sendNext(false)
				expect(enabled).toEventually(beFalsy())
				expect(action.isEnabled.value) == false
			}

			it("should execute the command once per start()") {
				let producer = action.apply(0 as NSNumber)
				expect(results) == []

				producer.start()
				expect(results).toEventually(equal([ 1 ]))

				producer.start()
				expect(results).toEventually(equal([ 1, 1 ]))

				let otherProducer = action.apply(2 as NSNumber)
				expect(results) == [ 1, 1 ]

				otherProducer.start()
				expect(results).toEventually(equal([ 1, 1, 3 ]))

				producer.start()
				expect(results).toEventually(equal([ 1, 1, 3, 1 ]))
			}
		}

		describe("toRACCommand") {
			var action: Action<NSNumber, NSString, TestError>!
			var results: [NSString] = []

			var enabledProperty: MutableProperty<Bool>!

			var command: RACCommand<NSNumber, NSString>!
			var enabled = false

			beforeEach {
				results = []
				enabledProperty = MutableProperty(true)

				action = Action(enabledIf: enabledProperty) { input in
					let inputNumber = input as Int
					return SignalProducer(value: "\(inputNumber + 1)" as NSString)
				}

				expect(action.isEnabled.value) == true

				action.values.observeValues { results.append($0) }

				command = action.toRACCommand()
				expect(command).notTo(beNil())

				command.enabled.subscribeNext { enabled = $0 as! Bool }
				expect(enabled) == true
			}

			it("should reflect the enabledness of the action") {
				enabledProperty.value = false
				expect(enabled).toEventually(beFalsy())

				enabledProperty.value = true
				expect(enabled).toEventually(beTruthy())
			}

			it("should apply and start a signal once per execution") {
				let signal = command.execute(0)

				do {
					try signal.asynchronouslyWaitUntilCompleted()
					expect(results) == [ "1" ]

					try signal.asynchronouslyWaitUntilCompleted()
					expect(results) == [ "1" ]

					try command.execute(2 as NSNumber).asynchronouslyWaitUntilCompleted()
					expect(results) == [ "1", "3" ]
				} catch {
					XCTFail("Failed to wait for completion")
				}
			}

			it("should bridge both inputs and ouputs with Optional<AnyObject>.none to nil in Objective-C") {
				var action: Action<Optional<AnyObject>, Optional<AnyObject>, TestError>!
				var command: RACCommand<AnyObject, AnyObject>!

				action = Action { input in
					return SignalProducer(value: input)
				}

				command = action.toRACCommand()
				expect(command).notTo(beNil())

				let racSignal = command.executionSignals.flatten().materialize().replay()

				command.execute(Optional<AnyObject>.none)

				let event = try! racSignal.asynchronousFirstOrDefault(nil, success: nil)
				expect(event.value).to(beNil())
			}

			it("should bridge outputs with Optional<AnyObject>.none to nil in Objective-C") {
				var action: Action<NSString, Optional<AnyObject>, TestError>!
				var command: RACCommand<NSString, AnyObject>!

				action = Action { _ in
					return SignalProducer(value: Optional<AnyObject>.none)
				}

				command = action.toRACCommand()
				expect(command).notTo(beNil())

				let racSignal = command.executionSignals.flatten().materialize().replay()

				command.execute("input" as NSString)

				let event = try! racSignal.asynchronousFirstOrDefault(nil, success: nil)
				expect(event.value).to(beNil())
			}

			it("should bridge inputs with Optional<AnyObject>.none to nil in Objective-C") {
				var action: Action<Optional<AnyObject>, NSString, TestError>!
				var command: RACCommand<AnyObject, NSString>!

				let inputSubject = RACSubject<AnyObject>()

				let inputSignal = RACSignal<NSNumber>
					.createSignal { subscriber in
						return inputSubject.subscribe(subscriber)
					}
					.replay()
					.materialize()

				action = Action { input in
					inputSubject.sendNext(input)
					return SignalProducer(value: "result")
				}

				command = action.toRACCommand()
				expect(command).notTo(beNil())

				command.execute(Optional<AnyObject>.none)

				let event = try! inputSignal.asynchronousFirstOrDefault(nil, success: nil)
				expect(event.value).to(beNil())
			}
		}

		describe("RACSubscriber.sendNext") {
			it("should have an argument of type Optional.none represented as `nil`") {
				let racSignal = RACSignal<AnyObject>.createSignal { subscriber in
					subscriber.sendNext(Optional<AnyObject>.none)
					subscriber.sendCompleted()
					return nil
				}

				let event = try! racSignal.materialize().asynchronousFirstOrDefault(nil, success: nil)
				let value = event.value
				expect(value).to(beNil())
			}
		}

		context("re tuples") {
			describe("bridgedTuple") {
				it("should bridge 1-tuples") {
					let racTuple = RACOneTuple<NSNumber>.pack(0)
					let tuple = bridgedTuple(from: racTuple)

					expect(tuple) == (0)
				}

				it("should bridge 2-tuples") {
					let racTuple = RACTwoTuple<NSNumber, NSNumber>.pack(0, 1)
					let tuple = bridgedTuple(from: racTuple)

					expect(Mirror(reflecting: tuple).children.count) == 2
					expect(tuple.0) == 0
					expect(tuple.1) == 1
				}

				it("should bridge 3-tuples") {
					let racTuple = RACThreeTuple<NSNumber, NSNumber, NSNumber>.pack(0, 1, 2)
					let tuple = bridgedTuple(from: racTuple)

					expect(Mirror(reflecting: tuple).children.count) == 3
					expect(tuple.0) == 0
					expect(tuple.1) == 1
					expect(tuple.2) == 2
				}

				it("should bridge 4-tuples") {
					let racTuple = RACFourTuple<NSNumber, NSNumber, NSNumber, NSNumber>.pack(0, 1, 2, 3)
					let tuple = bridgedTuple(from: racTuple)

					expect(Mirror(reflecting: tuple).children.count) == 4
					expect(tuple.0) == 0
					expect(tuple.1) == 1
					expect(tuple.2) == 2
					expect(tuple.3) == 3
				}

				it("should bridge 5-tuples") {
					let racTuple = RACFiveTuple<NSNumber, NSNumber, NSNumber, NSNumber, NSNumber>.pack(0, 1, 2, 3, 4)
					let tuple = bridgedTuple(from: racTuple)

					expect(Mirror(reflecting: tuple).children.count) == 5
					expect(tuple.0) == 0
					expect(tuple.1) == 1
					expect(tuple.2) == 2
					expect(tuple.3) == 3
					expect(tuple.4) == 4
				}

				it("should bridge tuples containing nils") {
					let racTuple = RACThreeTuple<NSString, NSString, NSString>.pack(nil, nil, nil)
					let tuple = bridgedTuple(from: racTuple)

					expect(Mirror(reflecting: tuple).children.count) == 3
					expect(tuple.0).to(beNil())
					expect(tuple.1).to(beNil())
					expect(tuple.2).to(beNil())
				}

				it("should bridge tuples containing both nils and values") {
					let racTuple = RACThreeTuple<NSString, NSString, NSString>.pack("rose", nil, "petal")
					let tuple = bridgedTuple(from: racTuple)

					expect(Mirror(reflecting: tuple).children.count) == 3
					expect(tuple.0) == "rose"
					expect(tuple.1).to(beNil())
					expect(tuple.2) == "petal"
				}
			}

			describe("bridgedSignalProducer") {
				it("should bridge signals of 1-tuples") {
					let racSignal = RACSignal<RACOneTuple<NSNumber>>.return(RACOneTuple<NSNumber>.pack(0))
					let producer = bridgedSignalProducer(from: racSignal)

					let value = producer.single()?.value as? (Int) ?? nil
					expect(value) == (0)
				}

				it("should bridge signals of 2-tuples") {
					let racSignal = RACSignal<RACTwoTuple<NSNumber, NSNumber>>.return(RACTwoTuple<NSNumber, NSNumber>.pack(0, 1))
					let producer = bridgedSignalProducer(from: racSignal)

					let value = producer.single()?.value ?? nil
					let valueMirror = value.map { Mirror(reflecting: $0) }
					expect(valueMirror?.children.count) == 2
					expect(value?.0) == 0
					expect(value?.1) == 1
				}

				it("should bridge signals of 3-tuples") {
					let racSignal = RACSignal<RACThreeTuple<NSNumber, NSNumber, NSNumber>>.return(RACThreeTuple<NSNumber, NSNumber, NSNumber>.pack(0, 1, 2))
					let producer = bridgedSignalProducer(from: racSignal).skipNil()

					let value = producer.single()?.value ?? nil
					let valueMirror = value.map { Mirror(reflecting: $0) }
					expect(valueMirror?.children.count) == 3
					expect(value?.0) == 0
					expect(value?.1) == 1
					expect(value?.2) == 2
				}

				it("should bridge signals of 4-tuples") {
					let racSignal = RACSignal<RACFourTuple<NSNumber, NSNumber, NSNumber, NSNumber>>.return(RACFourTuple<NSNumber, NSNumber, NSNumber, NSNumber>.pack(0, 1, 2, 3))
					let producer = bridgedSignalProducer(from: racSignal).skipNil()

					let value = producer.single()?.value ?? nil
					let valueMirror = value.map { Mirror(reflecting: $0) }
					expect(valueMirror?.children.count) == 4
					expect(value?.0) == 0
					expect(value?.1) == 1
					expect(value?.2) == 2
					expect(value?.3) == 3
				}

				it("should bridge signals of 5-tuples") {
					let racSignal = RACSignal<RACFiveTuple<NSNumber, NSNumber, NSNumber, NSNumber, NSNumber>>.return(RACFiveTuple<NSNumber, NSNumber, NSNumber, NSNumber, NSNumber>.pack(0, 1, 2, 3, 4))
					let producer = bridgedSignalProducer(from: racSignal).skipNil()

					let value = producer.single()?.value ?? nil
					let valueMirror = value.map { Mirror(reflecting: $0) }
					expect(valueMirror?.children.count) == 5
					expect(value?.0) == 0
					expect(value?.1) == 1
					expect(value?.2) == 2
					expect(value?.3) == 3
					expect(value?.4) == 4
				}

				it("should bridge signals of unnumbered tuples") {
					let racSignal = RACSignal<RACTuple>.return(RACTuple(objectsFrom: [0, 1]))
					let producer = bridgedSignalProducer(from: racSignal).skipNil()

					let value = producer.single()?.value
					expect(value?.count) == 2
					expect(value?.first as? Int) == 0
					expect(value?.second as? Int) == 1
					expect(value?.third).to(beNil())
				}
			}
		}
	}
}
