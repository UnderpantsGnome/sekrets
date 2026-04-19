module Sekrets::Tempfiles
  def tmpdir(&block)
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
      at_exit { FileUtils.rm_rf(dirname) if dirname && File.directory?(dirname) }
      dirname
    end
  end

  def tmpfile_for(basename, data)
    tmpfile = File.join(tmpdir, basename)
    IO.binwrite(tmpfile, data)
    tmpfile
  end

  def system(command)
    command = Array(command)

    if defined?(Bundler)
      if Bundler.respond_to?(:with_unbundled_env)
        Bundler.with_unbundled_env { Kernel.system(*command) }
      else
        message = Bundler.respond_to?(:with_original_env) ? :with_original_env : :with_clean_env
        Bundler.send(message) { Kernel.system(*command) }
      end
    else
      Kernel.system(*command)
    end

    $?.exitstatus
  end
end
