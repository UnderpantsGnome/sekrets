require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs = %w[lib test/lib]
  task.pattern = 'test/**/*_test.rb'
end

task default: :test
