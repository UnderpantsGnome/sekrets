Gem::Specification.new do |spec|
  spec.name = 'sekrets'
  spec.version = '1.14.0'
  spec.platform = Gem::Platform::RUBY
  spec.summary = 'securely manage encrypted files and settings'
  spec.description = "sekrets is a command line tool and library used to securely manage encrypted files and settings in your rails' applications and git repositories."
  spec.license = 'BSD-2-Clause'

  spec.files =
    ['Gemfile',
     'Gemfile.lock',
     'LICENSE',
     'README.md',
     'Rakefile',
     'bin',
     'bin/sekrets',
     'lib',
     'lib/sekrets',
     'lib/sekrets.rb',
     'lib/sekrets/capistrano.rb',
     'lib/sekrets/tasks',
     'lib/sekrets/tasks/capistrano2.rb',
     'lib/sekrets/tasks/sekrets.rake',
     'sekrets.gemspec',
     'test',
     'test/lib',
     'test/lib/testing.rb',
     'test/sekrets_test.rb']

  spec.executables = ['sekrets']

  spec.require_path = 'lib'

  spec.add_dependency('openssl', ' ~> 3.2')

  spec.author = 'Ara T. Howard'
  spec.email = 'ara.t.howard@gmail.com'
  spec.homepage = 'https://github.com/ahoward/sekrets'

  spec.required_ruby_version = '>= 3.2'
end
