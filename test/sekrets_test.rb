require 'fileutils'
require 'open3'
require 'pty'
require 'rbconfig'
require 'tmpdir'

TEST_DIR = __dir__
ROOT_DIR = File.expand_path('..', TEST_DIR)
LIB_DIR = File.join(ROOT_DIR, 'lib')

Dir.chdir(TEST_DIR)

require_relative 'lib/testing'
require_relative '../lib/sekrets'

Testing Sekrets do
  testing 'basic Sekrets.encrypt/Sekrets.decrypt functionality' do
    plaintext = '42'
    encrypted = assert { Sekrets.encrypt(:key, plaintext) }
    decrypted = assert { Sekrets.decrypt(:key, encrypted) }
    assert { decrypted == plaintext }
    assert { Sekrets.cycle(:key, plaintext) == plaintext }
  end

  testing 'Sekrets.key_for precedence' do
    environment = {
      'SEKRETS_KEY' => 'env key'
    }

    paths = {
      'plaintext' => 'plaintext',
      '.plaintext.key' => 'file key'
    }

    options = {
      key: 'options key'
    }

    with_environment(environment) do
      assert { Sekrets.key_for(options) == 'options key' }
    end

    with_environment(environment) do
      with_paths(paths) do
        assert { Sekrets.key_for(options) == 'options key' }
      end
    end

    with_environment(environment) do
      with_paths(paths) do
        assert { Sekrets.key_for(path: 'plaintext') == 'file key' }
        assert { Sekrets.key_for('plaintext') == 'file key' }
      end
    end

    with_environment(environment) do
      assert { Sekrets.key_for(path: 'plaintext') == 'env key' }
    end

    with_paths 'plaintext' => 'plaintext' do
      command = [ruby, '-r', File.join(LIB_DIR, 'sekrets.rb'), '-e', 'puts Sekrets.key_for("plaintext")']

      key = nil

      PTY.spawn(*command) do |r, w, _pid|
        w.puts('foobar')
        w.close
        key = begin
          r.gets.to_s.strip
        rescue StandardError
          Errno::EIO
        end
      end

      assert { key =~ /foobar/ }

      key, _status = Open3.capture2(*command, stdin_data: '')
      assert { key !~ /foobar/ }
    end
  end

  testing 'Sekrets.write/Secrets.read' do
    tmpdir do
      path = 'plaintext'
      content = 'content'
      key = '42'

      encrypted = assert { Sekrets.write(path, content, key) }

      assert { encrypted != content }
      assert { IO.read(path) != encrypted }
      assert { Sekrets.decrypt(key, encrypted) == content }
      assert { Sekrets.decrypt(key, IO.read(path)) == content }

      assert { Sekrets.read(path, key) == content }
    end
  end

  testing 'Sekrets.settings_for' do
    tmpdir do
      path = 'config.yml'
      config = { api_key: :val, a: :b, x: :y }
      content = config.to_yaml
      key = '42'

      assert { Sekrets.write(path, content, key) }
      settings = assert { Sekrets.settings_for(path, key) }
      assert { settings == config }
      assert { settings.api_key == :val }
      assert { settings[:a] == :b }
    end
  end

  testing 'Sekrets.settings_for wraps nested hashes' do
    tmpdir do
      path = 'nested.yml'
      config = {
        service: {
          api_key: 'abc123'
        },
        users: [
          { name: 'alice' }
        ]
      }

      Sekrets.write(path, config.to_yaml, '42')
      settings = Sekrets.settings_for(path, '42')

      assert { settings.service.api_key == 'abc123' }
      assert { settings.users.first.name == 'alice' }
    end
  end

  testing 'Sekrets.tmpdir cleans up temporary directories' do
    tmp = nil

    Sekrets.tmpdir do |dirname|
      tmp = dirname
      assert { Dir.pwd == dirname }
      IO.binwrite('marker.txt', 'ok')
      assert { File.size?('marker.txt') }
    end

    assert { !File.exist?(tmp) }
  end

  testing 'Sekrets.binstub invokes sekrets directly' do
    stub = Sekrets.binstub

    assert { !stub.include?('SEKRETS_ARGV') }
    assert { stub.include?("exec(Gem.bin_path('sekrets', 'sekrets'), *argv)") }
  end

  testing 'sekrets write and read cli round trip' do
    tmpdir do
      input = File.join(Dir.pwd, 'input.txt')
      encrypted = File.join(Dir.pwd, 'secret.enc')
      decrypted = File.join(Dir.pwd, 'output.txt')

      IO.binwrite(input, 'super secret')

      stdout, stderr, status = run_cli('write', encrypted, input, '-k', '42')
      assert { status.success? }
      assert { stdout.empty? }
      assert { stderr.empty? }
      assert { File.size?(encrypted) }

      stdout, stderr, status = run_cli('read', encrypted, decrypted, '-k', '42')
      assert { status.success? }
      assert { stdout.empty? }
      assert { stderr.empty? }
      assert { IO.binread(decrypted) == 'super secret' }
    end
  end

  testing 'sekrets read cli defaults to stdout' do
    tmpdir do
      encrypted = File.join(Dir.pwd, 'secret.enc')
      Sekrets.write(encrypted, 'from stdout', '42')

      stdout, stderr, status = run_cli('read', encrypted, '-k', '42')
      assert { status.success? }
      assert { stdout == 'from stdout' }
      assert { stderr.empty? }
    end
  end

  testing 'sekrets read cli accepts read-only encrypted files' do
    tmpdir do
      encrypted = File.join(Dir.pwd, 'secret.enc')
      Sekrets.write(encrypted, 'read only content', '42')
      File.chmod(0o444, encrypted)

      stdout, stderr, status = run_cli('read', encrypted, '-k', '42')
      assert { status.success? }
      assert { stdout == 'read only content' }
      assert { stderr.empty? }
    ensure
      File.chmod(0o644, encrypted) if File.exist?(encrypted)
    end
  end

  testing 'sekrets recrypt cli accepts repeated keys' do
    tmpdir do
      encrypted = File.join(Dir.pwd, 'secret.enc')
      Sekrets.write(encrypted, 'rotated secret', 'old-key')

      stdout, stderr, status = run_cli('recrypt', encrypted, '-k', 'old-key', '-k', 'new-key')
      assert { status.success? }
      assert { stdout.lines.last.to_s.strip == encrypted }
      assert { stderr.empty? }
      assert { Sekrets.read(encrypted, key: 'new-key') == 'rotated secret' }
    end
  end

  testing 'sekrets edit cli uses configured editor' do
    tmpdir do
      encrypted = File.join(Dir.pwd, 'secret.enc')
      editor = File.join(Dir.pwd, 'editor.sh')

      IO.binwrite(editor, "#!/bin/sh\nprintf 'edited content' > \"$1\"\n")
      File.chmod(0o755, editor)

      with_environment('SEKRETS_EDITOR' => editor) do
        stdout, stderr, status = run_cli('edit', encrypted, '-k', '42')
        assert { status.success? }
        assert { stdout.empty? }
        assert { stderr.empty? }
      end

      assert { Sekrets.read(encrypted, key: '42') == 'edited content' }
    end
  end

  testing 'sekrets read cli preserves existing output when decrypt fails' do
    tmpdir do
      encrypted = File.join(Dir.pwd, 'secret.enc')
      output = File.join(Dir.pwd, 'output.txt')

      Sekrets.write(encrypted, 'super secret', 'right-key')
      IO.binwrite(output, 'keep me')

      stdout, stderr, status = run_cli('read', encrypted, output, '-k', 'wrong-key')
      assert { !status.success? }
      assert { stdout.empty? }
      assert { stderr.include?('bad decrypt') }
      assert { IO.binread(output) == 'keep me' }
    end
  end

  testing 'sekrets cli without args prints help' do
    stdout, stderr, status = run_cli
    assert { status.success? }
    assert { stdout.include?('Usage: sekrets') }
    assert { stdout.include?('Commands:') }
    assert { stderr.empty? }
  end

  protected

  def with_paths(specification = {}, &block)
    tmpdir do |_tmp|
      specification.each do |path, contents|
        path = File.join(Dir.pwd, path.to_s)
        FileUtils.mkdir_p(File.dirname(path))

        File.binwrite(path, contents)
      end

      block.call
    end
  end

  def with_path(*args, &block)
    with_paths(*args, &block)
  end

  def with_environment(options = {}, &block)
    previous_values = {}
    previous_presence = {}

    options.each_key do |key|
      key = key.to_s
      previous_presence[key] = ENV.key?(key)
      previous_values[key] = ENV[key]
    end

    options.each do |key, val|
      ENV[key.to_s] = val.to_s
    end

    block.call
  ensure
    options.each do |key, _val|
      key = key.to_s

      if previous_presence[key]
        ENV[key] = previous_values[key]
      else
        ENV.delete(key)
      end
    end
  end

  def tmpdir(*args, &block)
    Sekrets.tmpdir(*args, &block)
  end

  def run_cli(*args, stdin_data: nil)
    env = { 'RUBYOPT' => nil }

    Open3.capture3(
      env,
      ruby,
      File.join(ROOT_DIR, 'bin', 'sekrets'),
      *args,
      stdin_data: stdin_data,
      chdir: Dir.pwd
    )
  end

  def ruby
    RbConfig.ruby
  end
end
