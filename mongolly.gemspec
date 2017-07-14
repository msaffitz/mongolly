# -*- encoding: utf-8 -*-
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "mongolly/version"

Gem::Specification.new do |gem|
  gem.name          = "mongolly"
  gem.version       = Mongolly::VERSION
  gem.authors       = ["Michael Saffitz"]
  gem.email         = ["m@saffitz.com"]
  gem.description   = "Easy backups for EBS-based MongoDB Databases"
  gem.summary       = "Easy backups for EBS-based MongoDB Databases"
  gem.homepage      = "http://www.github.com/msaffitz/mongolly"

  gem.files         = `git ls-files`.split($INPUT_RECORD_SEPARATOR)
  gem.executables   = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_dependency("thor")
  gem.add_dependency("mongo")
  gem.add_dependency("bson_ext")
  gem.add_dependency("aws-sdk", "~>1")
  gem.add_dependency("ipaddress")
  gem.add_dependency("net-ssh")
  gem.add_dependency("retries")
end
