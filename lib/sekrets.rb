class Sekrets
  class << self
    attr_writer :env, :editor, :root, :project_key, :global_key, :summary, :description
  end

  def self.env
    @env || 'SEKRETS_KEY'
  end

  def self.editor
    @editor || ENV['SEKRETS_EDITOR'] || ENV['EDITOR'] || 'vim'
  end

  def self.root
    return @root if defined?(@root) && !@root.nil?

    defined?(Rails.root) ? Rails.root : '.'
  end

  def self.project_key
    @project_key || File.join(root, '.sekrets.key')
  end

  def self.global_key
    @global_key || File.join(File.expand_path('~'), '.sekrets.key')
  end

  def self.summary
    @summary || 'securely manage encrypted files and settings'
  end

  def self.description
    @description ||
      "sekrets is a command line tool and library used to securely manage encrypted files and settings in your rails' applications and git repositories."
  end

  class Settings
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

  def self.extract_options!(args)
    args.last.is_a?(Hash) ? args.pop.dup : {}
  end

  def self.list_of_strings(*values)
    values.flatten.compact.map(&:to_s).reject(&:empty?)
  end

  def self.key_for(*args)
    options = extract_options!(args)
    path = args.shift || options[:path]

    if options.has_key?(:key)
      key = options[:key]
      return(key)
    end

    path = path_for(path)

    if path
      dirname, basename = File.split(path)

      keyfiles =
        list_of_strings(
          %i[keyfile keyfiles].map { |k| options[k] },
          %W[#{dirname}/.#{basename}.key #{dirname}/.#{basename}.k]
        )

      keyfiles.each do |file|
        if test('s', file)
          key = IO.binread(file).strip
          return(key)
        end
      end
    end

    return IO.binread(Sekrets.project_key).strip if Sekrets.project_key and test('s', Sekrets.project_key)

    env_key = (options[:env] || Sekrets.env).to_s
    if ENV.has_key?(env_key)
      key = ENV[env_key]
      return(key)
    end

    return IO.binread(Sekrets.global_key).strip if Sekrets.global_key and test('s', Sekrets.global_key)

    if !(options[:prompt] == false) && console?
      key = Sekrets.ask(path)
      return(key)
    end

    nil
  end

  def self.key_for!(*args, &block)
    key = Sekrets.key_for(*args, &block)
    raise(ArgumentError, 'no key!') unless key

    key
  end

  def self.read(*args)
    options = extract_options!(args)
    path = args.shift || options[:path]
    key = args.shift || Sekrets.key_for!(path, options)

    return nil unless test('s', path)

    encrypted = IO.binread(path)
    decrypted = Sekrets.decrypt(key, encrypted)
    new(decrypted)
  end

  def self.write(*args)
    options = extract_options!(args)
    path = args.shift || options[:path]
    content = args.shift || options[:content]
    key = args.shift || Sekrets.key_for!(path, options)

    dirname, = File.split(File.expand_path(path))
    FileUtils.mkdir_p(dirname)

    encrypted = Sekrets.encrypt(key, content)

    tmp = path + '.tmp'
    IO.binwrite(tmp, encrypted)
    FileUtils.mv(tmp, path)
    new(encrypted)
  end

  def self.settings_for(*args, &block)
    decrypted = read(*args, &block)

    return unless decrypted

    expanded = ERB.new(decrypted).result(TOPLEVEL_BINDING)
    object = YAML.load(expanded)
    object.is_a?(Hash) ? Settings.for(object) : object
  end

  def self.prompt_for(*words)
    ['sekrets:', words, '> '].flatten.compact.join(' ')
  end

  def self.ask(question)
    print prompt_for(question)
    gets.strip
  end

  def self.console?
    STDIN.tty?
  end

  def self.tmpdir(&block)
    prefix = "sekrets-#{Process.ppid}-#{Process.pid}-"

    if block
      Dir.mktmpdir(prefix) do |dirname|
        dirname = File.realpath(dirname)

        Dir.chdir(dirname) do
          block.call(dirname)
        end
      end
    else
      dirname = Dir.mktmpdir(prefix)
      dirname = File.realpath(dirname)
      at_exit { FileUtils.rm_rf(dirname) if dirname && test('d', dirname) }
      dirname
    end
  end

  def self.tmpfile_for(basename, data)
    tmpfile = File.join(Sekrets.tmpdir, basename)
    IO.binwrite(tmpfile, data)
    tmpfile
  end

  def self.system(command)
    command = Array(command)

    if defined?(Bundler)
      if Bundler.respond_to?(:with_unbundled_env)
        Bundler.with_unbundled_env { Kernel.system(*command) }
      else
        msg = (Bundler.respond_to?(:with_original_env) ? :with_original_env : :with_clean_env)
        Bundler.send(msg) { Kernel.system(*command) }
      end
    else
      Kernel.system(*command)
    end

    $?.exitstatus
  end

  def self.openw(arg, &block)
    opened = false
    atomic_move = proc {}

    io =
      if arg.respond_to?(:read)
        arg
      elsif arg.to_s.strip == '-'
        STDOUT
      else
        opened = true
        path = File.expand_path(arg.to_s)
        dirname, = File.split(path)
        FileUtils.mkdir_p(dirname)
        tmp = path + ".sekrets.tmp.#{Process.ppid}.#{Process.pid}"
        at_exit { FileUtils.rm_f(tmp) }
        atomic_move = proc { FileUtils.mv(tmp, path) }
        open(tmp, 'wb+')
      end

    close =
      proc do
        io.close if opened
        atomic_move.call
      end

    if block
      begin
        block.call(io)
      ensure
        close.call
      end
    else
      at_exit { close.call }
      io
    end
  end

  def self.openr(arg, &block)
    opened = false

    io =
      if arg.respond_to?(:read)
        arg
      elsif arg.to_s.strip == '-'
        STDIN
      else
        opened = true
        open(arg, 'rb+')
      end

    close =
      proc do
        io.close if opened
      end

    if block
      begin
        block.call(io)
      ensure
        close.call
      end
    else
      at_exit { close.call }
      io
    end
  end

  def self.path_for(object)
    path = nil

    return(path = object.to_s) if object.is_a?(String) or object.is_a?(Pathname)

    %i[original_path original_filename path filename pathname].each do |msg|
      if object.respond_to?(msg)
        path = object.send(msg)
        break
      end
    end

    path
  end

  def self.binstub
    @binstub ||= unindent(
      <<-_V_
          #! /usr/bin/env ruby

          dirname = File.expand_path(File.dirname(__FILE__))
          root = File.dirname(dirname)
          ciphertext = File.join(dirname, 'ciphertext')

          argv =
            case ARGV.length
            when 0
              ['edit', ciphertext]
            when 1
              [ARGV.first, ciphertext]
            else
              ARGV
            end

          ENV['BUNDLE_GEMFILE'] ||= File.join(root, 'Gemfile')

          require 'rubygems'
          require 'bundler/setup'

          key = File.join(root, '.sekrets.key')

          if test(?s, key)
            ENV['SEKRETS_KEY'] = IO.binread(key).strip
          end

          exec(Gem.bin_path('sekrets', 'sekrets'), *argv)
      _V_
    )
  end

  def self.unindent(string)
    indent = string.split("\n").select { |line| !line.strip.empty? }.map { |line| line.index(/[^\s]/) }.compact.min || 0
    string.gsub(/^[[:blank:]]{#{indent}}/, '')
  end

  module Blowfish
    def cipher(mode, key, data)
      cipher =
        begin
          ::OpenSSL::Cipher.new('bf-cbc').send(mode)
        rescue StandardError => e
          raise if
            @openssl_is_already_monkey_patched or
            (e.class.name != 'OpenSSL::Cipher::CipherError') or
            !defined?(::OpenSSL::Provider)

          @openssl_is_already_monkey_patched = true
          ::OpenSSL::Provider.load('legacy')
          ::OpenSSL::Cipher.new('bf-cbc').send(mode)
        end

      cipher.key = ::Digest::SHA256.digest(key.to_s).slice(0, 16)

      cipher.update(data) << cipher.final
    end

    def encrypt(key, data)
      cipher(:encrypt, key, data)
    end

    def decrypt(key, text)
      cipher(:decrypt, key, text)
    end

    def cycle(key, data)
      decrypt(key, encrypt(key, data))
    end

    def recrypt(old_key, new_key, data)
      encrypt(new_key, decrypt(old_key, data))
    end

    extend(self)
  end

  extend(Blowfish)
end

Sekret = Sekrets

BEGIN {

  require 'openssl'
  require 'fileutils'
  require 'erb'
  require 'yaml'
  require 'tmpdir'

  class Sekrets < ::String
    Version = '1.14.0' unless defined?(Version)

    class << Sekrets
      def version
        Sekrets::Version
      end

      def dependencies
        {
          'openssl' => ['openssl', ' ~> 3.2']
        }
      end

      def libdir(*args, &block)
        @libdir ||= File.expand_path(__FILE__).sub(/\.rb$/, '')
        args.empty? ? @libdir : File.join(@libdir, *args)
      ensure
        if block
          begin
            $LOAD_PATH.unshift(@libdir)
            block.call
          ensure
            $LOAD_PATH.shift
          end
        end
      end

      def load(*libs)
        libs = libs.join(' ').scan(/[^\s+]+/)
        Sekrets.libdir { libs.each { |lib| Kernel.load(lib) } }
      end
    end
  end

  begin
    require 'rubygems'
  rescue LoadError
    nil
  end

  Sekrets.dependencies.each do |lib, dependency|
    gem(*dependency) if defined?(gem)
    require(lib)
  end

  if defined?(Rails)

    class Sekrets
      class Engine < Rails::Engine
        engine_name :sekrets

        rake_tasks do
          namespace :sekrets do
            namespace :generate do
              desc 'generate a .sekrets.key'
              task :key do
                keyfile = File.join(Rails.root, '.sekrets.key')
                abort("#{keyfile} exists!") if test('e', keyfile)
                key = SecureRandom.hex
                open(keyfile, 'wb') { |fd| fd.puts(key) }

                begin
                  gitignore = File.join(Rails.root, '.gitignore')
                  buf = IO.read(gitignore)

                  unless /\.sekrets\.key/.match?(buf)
                    open(gitignore, 'a+') do |fd|
                      fd.puts
                      fd.puts '.sekrets.key'
                      fd.puts
                    end
                  end
                rescue Object
                end

                puts "created #{Rails.root}/.sekrets.key"
                puts 'do *NOT* commit this file'
                puts
                puts "updated #{Rails.root}/.gitignore"
                puts 'yes *DO* commit this file'
                puts
                puts '*** YOU NEED TO DISTRIBUTE THIS KEY TO YOUR TEAM ***'
                puts
                puts '*** YOU NEED DEPLOY THIS KEY WITH YOUR APPLICATION ***'
                puts
                puts "hint: require 'sekrets/capistrano' in your Capfile"
                puts
              end

              desc 'generate a secure editor for plaintext application sekrets'
              task :editor do
                keyfile = File.join(Rails.root, '.sekrets.key')
                abort("run 'rake sekrets:generate:key' first") unless test('e', keyfile)
                key = IO.binread(keyfile).strip

                editor = File.join(Rails.root, 'sekrets', 'editor')
                ciphertext = File.join(Rails.root, 'sekrets', 'ciphertext')

                unless test('s', editor)
                  FileUtils.mkdir_p(File.dirname(editor))
                  open(editor, 'wb') { |fd| fd.write(Sekrets.binstub) }
                  File.chmod(0o755, editor)
                  puts "created #{editor}"
                end

                unless test('s', ciphertext)
                  content = "# store sensitive infomation like credit cards, ssh keys, and passwords here\n\n\n"
                  Sekrets.write(ciphertext, content, key: key)
                  puts "created #{ciphertext}"
                end

                puts 'run ./sekrets/editor to edit ./sekrets/ciphertext'
              end

              desc 'generate a secure config for application sekrets'
              task :config do
                keyfile = File.join(Rails.root, '.sekrets.key')
                abort("run 'rake sekrets:generate:key' first") unless test('e', keyfile)
                key = IO.binread(keyfile).strip

                config = File.join(Rails.root, 'config', 'sekrets.yml.enc')
                unless test('s', config)
                  FileUtils.mkdir_p(File.dirname(config))
                  require 'yaml' unless defined?(YAML)
                  content = { 'api_key' => 42 }.to_yaml
                  Sekrets.write(config, content, key: key)
                  puts "created #{config}"
                end

                initializer = File.join(Rails.root, 'config', 'initializers', 'sekrets.rb')
                unless test('s', initializer)
                  FileUtils.mkdir_p(File.dirname(initializer))
                  open(initializer, 'wb') do |fd|
                    code = <<-__

                      config = File.join(Rails.root, 'config', 'sekrets.yml.enc')
                      key = File.join(Rails.root, '.sekrets.key')

                      if test(?e, config)
                        if test(?e, key)
                          SEKRETS = Sekrets.settings_for(config)
                        else
                          SEKRETS = Sekrets::Settings.new
                          warn "missing \#{ key }!"
                        end
                      end

                    __
                    fd.puts(code)
                  end
                  puts "created #{initializer}"
                end
              end
            end
          end
        end
      end
    end

  end
}
