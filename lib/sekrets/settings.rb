class Sekrets::Settings
  include Enumerable

  class << self
    def for(object = nil)
      return object if object.is_a?(self)
      return object unless object.is_a?(Hash)

      new(object)
    end
  end

  def initialize(source = nil)
    @data = {}
    merge!(source || {})
  end

  def [](key)
    wrap(fetch_value(key))
  end

  def fetch(key, *args, &block)
    return self[key] if key?(key)

    return args.first unless args.empty?
    return block.call(key) if block

    raise KeyError, "key not found: #{key.inspect}"
  end

  def []=(key, value)
    @data[key] = unwrap(value)
  end

  def merge!(other)
    other.each do |key, value|
      self[key] = value
    end

    self
  end

  def each(&block)
    return enum_for(:each) unless block

    @data.each do |key, value|
      block.call(key, wrap(value))
    end
  end

  def method_missing(name, *args, &block)
    return self[name] if args.empty? && key_lookup?(name)

    super
  end

  def respond_to_missing?(name, include_private = false)
    key_lookup?(name) || super
  end

  def key?(key)
    key_lookup?(key)
  end

  def empty?
    @data.empty?
  end

  def keys
    @data.keys
  end

  def values
    @data.values.map { |value| wrap(value) }
  end

  def dig(*keys)
    current = self

    keys.each do |key|
      return nil unless current.respond_to?(:[])

      current = current[key]
    end

    current
  end

  def to_h
    deep_copy(@data)
  end

  def ==(other)
    other = other.to_h if other.respond_to?(:to_h)
    to_h == other
  end

  def inspect
    @data.inspect
  end

  private

  def key_lookup?(name)
    @data.key?(name) || @data.key?(name.to_s) || @data.key?(symbolize_key(name))
  end

  def fetch_value(key)
    return @data[key] if @data.key?(key)

    symbolized = symbolize_key(key)
    return @data[symbolized] if symbolized && @data.key?(symbolized)

    stringified = key.to_s
    return @data[stringified] if @data.key?(stringified)

    nil
  end

  def symbolize_key(key)
    key.respond_to?(:to_sym) ? key.to_sym : nil
  end

  def wrap(value)
    case value
    when Hash
      self.class.new(value)
    when Array
      value.map { |entry| wrap(entry) }
    else
      value
    end
  end

  def unwrap(value)
    value.is_a?(self.class) ? value.to_h : value
  end

  def deep_copy(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, entry), object|
        object[key] = deep_copy(entry)
      end
    when Array
      value.map { |entry| deep_copy(entry) }
    else
      value
    end
  end
end
