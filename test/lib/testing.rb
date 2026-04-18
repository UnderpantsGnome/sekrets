require 'minitest/autorun'

module TestingSupport
  class << self
    attr_accessor :suite_count
  end

  self.suite_count = 0

  def self.slug_for(*args)
    string = args.flatten.compact.join('-')
    words = string.to_s.scan(/\w+/)
    words.map! { |word| word.gsub(/[^0-9a-zA-Z_-]/, '') }
    words.reject! { |word| word.nil? || word.strip.empty? }
    words.join('-').downcase
  end
end

def Testing(*args, &block)
  TestingSupport.suite_count += 1

  slug = TestingSupport.slug_for(*args).tr('-', '_')
  name = ['TESTING', format('%03d', TestingSupport.suite_count), slug].reject(&:empty?).join('_').upcase

  klass = Class.new(Minitest::Test) do
    class << self
      def testno
        @testno ||= 0
        current = format('%05d', @testno)
        @testno += 1
        current
      end

      def testing(*test_args, &test_block)
        slug = TestingSupport.slug_for(*test_args).tr('-', '_')
        define_method("test_#{testno}_#{slug}", &test_block)
      end
    end

    alias_method :__minitest_assert__, :assert

    def assert(*args, &block)
      if block
        result = block.call
        __minitest_assert__(result, args.join(' '))
        result
      else
        result = args.shift
        __minitest_assert__(result, args.join(' '))
        result
      end
    end

    alias_method :__minitest_assert_raises__, :assert_raises

    def assert_raises(*args, &block)
      args = [Exception] if args.empty?
      __minitest_assert_raises__(*args, &block)
    end
  end

  Object.send(:remove_const, name) if Object.const_defined?(name, false)
  Object.const_set(name, klass)

  klass.class_eval(&block)
  klass
end
