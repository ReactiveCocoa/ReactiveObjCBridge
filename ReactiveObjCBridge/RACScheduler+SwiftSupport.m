#import <RACScheduler+SwiftSupport.h>
#import <ReactiveObjC/ReactiveObjC.h>

@implementation RACScheduler (SwiftSupport)
+ (RACScheduler *)schedulerWithRACSwiftScheduler:(RACScheduler *)scheduler {
	return scheduler;
}
@end
