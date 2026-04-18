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
      command = %[ #{ruby} -r #{$libdir}/sekrets.rb -e'puts Sekrets.key_for("plaintext")' ]

      key = nil

      PTY.spawn(command) do |r, w, _pid|
        w.puts('foobar')
        w.close
        key = begin
          r.gets.to_s.strip
        rescue StandardError
          Errno::EIO
        end
      end

      assert { key =~ /foobar/ }

      key = `#{command} </dev/null`
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
      assert { test('s', 'marker.txt') }
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
      assert { test('s', encrypted) }

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

        open(path, 'wb') { |fd| fd.write(contents) }
      end

      block.call
    end
  end

  def with_path(*args, &block)
    with_paths(*args, &block)
  end

  def with_environment(options = {}, &block)
    options.each do |key, val|
      ENV[key.to_s] = val.to_s
    end
    block.call
  ensure
    options.each do |key, _val|
      ENV.delete(key.to_s)
    end
  end

  def tmpdir(*args, &block)
    Sekrets.tmpdir(*args, &block)
  end

  def run_cli(*args, stdin_data: nil)
    env = {
      'RUBYOPT' => nil
    }

    Open3.capture3(
      env,
      ruby,
      File.join($rootdir, 'bin', 'sekrets'),
      *args,
      stdin_data: stdin_data,
      chdir: Dir.pwd
    )
  end

  def ruby
    @ruby ||= begin
      c = RbConfig::CONFIG
      bindir = c['bindir'] || c['BINDIR']
      ruby_install_name = c['ruby_install_name'] || c['RUBY_INSTALL_NAME'] || 'ruby'
      ruby_ext = c['EXEEXT'] || ''
      File.join(bindir, ruby_install_name + ruby_ext)
    end
  end
end

BEGIN {
  $testdir = File.dirname(File.expand_path(__FILE__))
  $testlibdir = File.join($testdir, 'lib')
  $rootdir = File.dirname($testdir)
  $libdir = File.join($rootdir, 'lib')
  $LOAD_PATH.push($libdir)
  $LOAD_PATH.push($testlibdir)

  Dir.chdir($testdir)

  require 'tmpdir'
  require 'fileutils'
  require 'pty'
  require 'open3'

  require 'testing'
  require 'sekrets'
}
