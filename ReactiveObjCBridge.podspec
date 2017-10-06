Pod::Spec.new do |s|
  s.name         = "ReactiveObjCBridge"
  s.version      = "2.0.0"
  s.summary      = "Bridge between ReactiveObjC and ReactiveSwift"
  s.description  = <<-DESC
                   After the announcement of Swift, ReactiveCocoa was rewritten in Swift. This framework creates a bridge between those Swift and Objective-C APIs (now known as ReactiveSwift and ReactiveObjC respectively).

                   Because the APIs are based on fundamentally different designs, the conversion is not always one-to-one; however, every attempt has been made to faithfully translate the concepts between the two APIs (and languages).
                   DESC
  s.homepage     = "https://github.com/ReactiveCocoa/ReactiveObjCBridge"
  s.license      = { :type => "MIT", :file => "LICENSE.md" }
  s.author       = "ReactiveCocoa"

  s.osx.deployment_target = "10.9"
  s.ios.deployment_target = "8.0"
  s.tvos.deployment_target = "9.0"
  s.watchos.deployment_target = "2.0"

  s.source       = { :git => "https://github.com/ReactiveCocoa/ReactiveObjCBridge.git", :tag => "#{s.version}" }
  s.source_files = "ReactiveObjCBridge/*.{swift,h,m}"
  s.private_header_files = 'ReactiveObjCBridge/RACScheduler+SwiftSupport.h'
  s.module_map = 'ReactiveObjCBridge/module.modulemap'

  s.dependency 'ReactiveObjC', '~> 3.0.0'
  s.dependency 'ReactiveSwift', '2.1.0-alpha.2'

  s.pod_target_xcconfig = { "OTHER_SWIFT_FLAGS[config=Release]" => "-suppress-warnings" }
end
