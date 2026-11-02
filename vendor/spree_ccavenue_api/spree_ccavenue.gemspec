# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)
require 'spree_ccavenue/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_ccavenue'
  s.version     = SpreeCcavenue.version
  s.summary     = 'CCAvenue payment gateway support for Spree'
  s.description = 'CCAvenue is a payment gateway in India. This gem provides support for CCAvenue in Spree Commerce'
  s.required_ruby_version = '>= 3.0.0'
  s.author      = 'Varasala RatnamRaju'
  s.email       = 'ratnam.raju@gmail.com'
  s.homepage    = 'http://ccavenue.com/'
  s.license     = 'BSD-3-Clause'
  
  s.files       = Dir["**/*"].reject { |f| f.match(/^spec/) && !f.match(/^spec\/fixtures/) }
  s.require_path = 'lib'
  s.requirements << 'none'
  
  # ✅ Updated to support Rails 8 and Spree 5.x
  spree_version = '>= 5.1.0'
  s.add_dependency 'rails', '>= 7.0.0', '< 9.0.0'  # Changed to support Rails 8
  s.add_dependency 'spree', spree_version
  s.add_dependency 'spree_extension'
  s.add_dependency 'rest-client', '~> 2.1'
  
  s.add_development_dependency 'spree_dev_tools'
end