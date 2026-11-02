# encoding: UTF-8
lib = File.expand_path('../lib/', __FILE__)
$LOAD_PATH.unshift lib unless $LOAD_PATH.include?(lib)

require 'spree_cashfree/version'

Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_cashfree'
  s.version     = SpreeCashfree.version
  s.summary     = 'Cashfree payment gateway support for Spree'
  s.description = 'Cashfree is a payment gateway in India. This gem provides support for Cashfree in Spree Commerce'
  s.required_ruby_version = '>= 3.0.0'
  
  s.author      = 'Your Name'
  s.email       = 'your.email@example.com'
  s.homepage    = 'https://cashfree.com/'
  s.license     = 'BSD-3-Clause'
  
  s.files       = Dir["**/*"].reject { |f| f.match(/^spec/) && !f.match(%r{^spec/fixtures}) }
  s.require_path = 'lib'
  s.requirements << 'none'
  
  spree_version = '>= 5.1.0'
  s.add_dependency 'rails', '>= 7.0.0', '< 9.0.0'
  s.add_dependency 'spree', spree_version
  s.add_dependency 'spree_extension'
  s.add_dependency 'rest-client', '~> 2.1'
  
  s.add_development_dependency 'spree_dev_tools'
end