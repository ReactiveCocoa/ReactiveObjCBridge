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
			var scheduler: DateSchedulerProtocol!

			beforeEach {
				originalScheduler = RACTestScheduler()
				scheduler = originalScheduler as DateSchedulerProtocol
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

				let producer = signalProducer(from: racSignal).map { $0 as! Int }

				expect((producer.single())?.value) == 0
				expect((producer.single())?.value) == 1
				expect((producer.single())?.value) == 2
			}

			it("should forward errors")	{
				let error = TestError.default as NSError

				let racSignal = RACSignal<AnyObject>.error(error)
				let producer = signalProducer(from: racSignal)
				let result = producer.last()

				expect(result?.error) == error
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
					let producer = SignalProducer<Optional<Any>, NSError>(value: nil)
					let racSignal = producer.toRACSignal().materialize()
					
					let event = racSignal.first() as? RACEvent
					expect(event?.value).to(beNil())
				}
			}

			describe("on a SignalProducer") {
				it("should start once per subscription") {
					var subscriptions = 0

					let producer = SignalProducer<NSNumber, NoError>.attempt {
						defer {
							subscriptions += 1
						}

						return .success(subscriptions as NSNumber)
					}
					let racSignal = producer.toRACSignal()

					expect(racSignal.first() as? NSNumber) == 0
					expect(racSignal.first() as? NSNumber) == 1
					expect(racSignal.first() as? NSNumber) == 2
				}

				it("should convert errors to NSError") {
					let producer = SignalProducer<AnyObject, TestError>(error: .error1)
					let racSignal = producer.toRACSignal().materialize()

					let event = racSignal.first() as? RACEvent
					expect(event?.error as? NSError) == TestError.error1 as NSError
				}
				
				it("should maintain userInfo on NSError") {
					let producer = SignalProducer<AnyObject, NSError>(error: testNSError)
					let racSignal = producer.toRACSignal().materialize()
					
					let event = racSignal.first() as? RACEvent
					let userInfoValue = event?.error?.localizedDescription
					expect(userInfoValue) == userInfo[key]
				}
				
				it("should bridge next events with value Optional<Any>.none to nil in Objective-C") {
					let producer = SignalProducer<Optional<Any>, NSError>(value: nil)
					let racSignal = producer.toRACSignal().materialize()
					
					let event = racSignal.first() as? RACEvent
					expect(event?.value).to(beNil())
				}
			}
		}

		describe("toAction") {
			var command: RACCommand<NSNumber, NSNumber>!
			var results: [Int] = []

			var enabledSubject: RACSubject!
			var enabled = false

			var action: Action<NSNumber?, NSNumber?, NSError>!

			beforeEach {
				enabledSubject = RACSubject()
				results = []

				let enabledSignal = RACSignal<NSNumber>.createSignal({ subscriber in
					return enabledSubject.subscribe(subscriber)
				})

				command = RACCommand<NSNumber, NSNumber>(enabled: enabledSignal) { input in
					let inputNumber = input as! Int
					return RACSignal<NSNumber>.`return`(inputNumber + 1)
				}

				expect(command).notTo(beNil())

				command.enabled.subscribeNext { enabled = $0 as! Bool }
				expect(enabled) == true

				let values = signalProducer(from: command.executionSignals)
					.map { signalProducer(from: $0!) }
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
			var action: Action<AnyObject?, NSString, TestError>!
			var results: [NSString] = []

			var enabledProperty: MutableProperty<Bool>!

			var command: RACCommand<AnyObject, NSString>!
			var enabled = false
			
			beforeEach {
				results = []
				enabledProperty = MutableProperty(true)

				action = Action(enabledIf: enabledProperty) { input in
					let inputNumber = input as! Int
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
				let signal = command.execute(0 as NSNumber)

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
		}
		
		describe("RACSubscriber.sendNext") {
			
			it("should have an argument of type Optional.none represented as `nil`") {
				let racSignal = RACSignal.createSignal { subscriber in
					subscriber.sendNext(Optional<Any>.none)
					subscriber.sendCompleted()
					return nil
				}
				
				let event = racSignal.first() as? RACEvent
				let value = event?.value
				expect(value).to(beNil())
			}
		}
	}
}
