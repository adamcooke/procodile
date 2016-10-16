Gem::Specification.new do |s|
  s.name          = "procodile"
  s.description   = %q{Run Ruby/Rails processes in the background on Linux servers with ease.}
  s.summary       = %q{This gem will help you run Ruby processes from a Procfile on Linux servers in the background.}
  s.homepage      = "https://github.com/adamcooke/procodile"
  s.version       = '0.0.2'
  s.files         = Dir.glob("{lib,bin}/**/*")
  s.require_paths = ["lib"]
  s.authors       = ["Adam Cooke"]
  s.email         = ["me@adamcooke.io"]
  s.licenses      = ['MIT']
  s.bindir = "bin"
  s.executables << 'procodile'
  s.add_runtime_dependency 'json'
end
