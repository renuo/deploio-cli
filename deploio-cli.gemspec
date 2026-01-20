# frozen_string_literal: true

require_relative 'lib/deploio/version'

Gem::Specification.new do |spec|
  spec.name = 'deploio-cli'
  spec.version = Deploio::VERSION
  spec.authors = ['Renuo AG']
  spec.email = ['info@renuo.ch']

  spec.summary = 'CLI for Deploio'
  spec.description = 'A Ruby CLI that provides an interface for managing Deploio applications.'
  spec.homepage = 'https://github.com/renuo/deploio-cli'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'bin'
  spec.executables = ['deploio']
  spec.require_paths = ['lib']

  spec.add_dependency 'thor', '~> 1.3'
  spec.add_dependency 'tty-table', '~> 0.12'
end
