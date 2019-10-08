require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name     = "react-native-sqlcipher-storage"
  s.version  = package['version']
  s.summary  = package['description']
  s.homepage = package['homepage']
  s.license  = package['license']
  s.authors  = package['author']
  s.source   = { :git => package['repository']['url'], :tag => "v#{s.version}" }

  s.ios.deployment_target = '9.0'
  s.osx.deployment_target = '10.10'

  s.preserve_paths = 'README.md', 'LICENSE', 'package.json', 'sqlite.js'
  s.source_files   = "src/common/*.{c,h,m}", "src/ios/*.{c,h,m}"

  s.dependency 'React'
  
end
