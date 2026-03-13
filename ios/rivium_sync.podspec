Pod::Spec.new do |s|
  s.name             = 'rivium_sync'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for RiviumSync realtime database SDK'
  s.description      = <<-DESC
Flutter plugin for RiviumSync — realtime database SDK with offline-first sync
powered by pn-protocol.
                       DESC
  s.homepage         = 'https://rivium.co/'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Rivium' => 'founder@rivium.co' }
  s.source           = { :path => '.' }

  # Includes both Flutter plugin bridge and native SDK source
  s.source_files = 'Classes/**/*'

  s.dependency 'Flutter'
  s.dependency 'CocoaMQTT', '~> 2.1'

  s.platform = :ios, '13.0'
  s.swift_version = '5.7'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
