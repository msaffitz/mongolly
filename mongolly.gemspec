# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mongolly/version'

Gem::Specification.new do |gem|
  gem.name          = "mongolly"
  gem.version       = Mongolly::VERSION
  gem.authors       = ["Michael Saffitz"]
  gem.email         = ["m@saffitz.com"]
  gem.description   = %q{Easy backups for EBS-based MongoDB Databases}
  gem.summary       = %q{Easy backups for EBS-based MongoDB Databases}
  gem.homepage      = "http://www.github.com/msaffitz/mongolly"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency("thor", ["~> 0.15.4"])
  gem.add_dependency("mongo", ["~> 1.7.0"])
  gem.add_dependency("bson_ext", ["~> 1.7.0"])
  gem.add_dependency("aws-sdk", ["~> 1.5.8"])

end
