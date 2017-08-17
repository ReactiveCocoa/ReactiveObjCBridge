#import <ReactiveObjC/ReactiveObjC.h>

@interface RACScheduler (SwiftSupport)
+ (RACScheduler *)schedulerWithRACSwiftScheduler:(RACScheduler *)scheduler;
@end
