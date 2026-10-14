Pod::Spec.new do |s|
  s.name = 'Reception'
  s.version = File.read(File.join(__dir__, 'Sources/Reception/Version.swift'))[/static let current = "([^"]+)"/, 1]
  s.summary = 'Native in-app support chat for iOS.'
  s.homepage = 'https://reception.sh'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'Reception'
  s.source = { :git => 'https://github.com/reception-sh/reception-ios.git', :tag => s.version.to_s }
  s.ios.deployment_target = '17.0'
  s.swift_version = '5.0'
  s.source_files = 'Sources/Reception/**/*.swift'
  s.resource_bundles = { 'Reception' => ['Sources/Reception/Resources/Localizable.xcstrings', 'Sources/Reception/Resources/PrivacyInfo.xcprivacy'] }
  s.pod_target_xcconfig = { 'SWIFT_STRICT_CONCURRENCY' => 'complete', 'DEFINES_MODULE' => 'YES' }
end
