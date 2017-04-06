Pod::Spec.new do |s|
  s.name         = "ReactiveObjCBridge"
  s.version      = "1.0.1"
  s.summary      = "Bridge between ReactiveObjC and ReactiveSwift"
  s.description  = <<-DESC
                   After announced Swift, ReactiveCocoa was rewritten in Swift. This framework creates a bridge between those Swift and Objective-C APIs (ReactiveSwift and ReactiveObjC).
                   
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
  s.source_files = "ReactiveObjCBridge/*.{swift}"

  s.dependency 'ReactiveObjC', '~> 2.1.2'
  s.dependency 'ReactiveSwift', '~> 1.1'

  s.pod_target_xcconfig = { "OTHER_SWIFT_FLAGS[config=Release]" => "-suppress-warnings" }
end
