module Sekrets::Files
  def read(*args)
    options = extract_options!(args)
    path = args.shift || options[:path]
    key = args.shift || key_for!(path, options)

    return nil unless File.size?(path)

    encrypted = IO.binread(path)
    decrypted = decrypt(key, encrypted)
    new(decrypted)
  end

  def write(*args)
    options = extract_options!(args)
    path = args.shift || options[:path]
    content = args.shift || options[:content]
    key = args.shift || key_for!(path, options)

    dirname, = File.split(File.expand_path(path))
    FileUtils.mkdir_p(dirname)

    encrypted = encrypt(key, content)

    tmp = path + '.tmp'
    IO.binwrite(tmp, encrypted)
    FileUtils.mv(tmp, path)
    new(encrypted)
  end

  def settings_for(*args, &block)
    decrypted = read(*args, &block)

    return unless decrypted

    expanded = ERB.new(decrypted).result(TOPLEVEL_BINDING)
    object = YAML.load(expanded)
    object.is_a?(Hash) ? Sekrets::Settings.for(object) : object
  end

  def openw(arg, &block)
    opened = false
    atomic_move = proc {}
    cleanup = proc {}

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
        cleanup = proc { FileUtils.rm_f(tmp) }
        File.open(tmp, 'wb+')
      end

    close =
      proc do |commit|
        io.close if opened
        if commit
          atomic_move.call
        else
          cleanup.call
        end
      end

    if block
      committed = false

      begin
        block.call(io)
        committed = true
      ensure
        close.call(committed)
      end
    else
      at_exit { close.call(true) }
      io
    end
  end

  def openr(arg, &block)
    opened = false

    io =
      if arg.respond_to?(:read)
        arg
      elsif arg.to_s.strip == '-'
        STDIN
      else
        opened = true
        File.open(arg, 'rb')
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

  def path_for(object)
    path = nil

    return object.to_s if object.is_a?(String) || object.is_a?(Pathname)

    %i[original_path original_filename path filename pathname].each do |message|
      if object.respond_to?(message)
        path = object.send(message)
        break
      end
    end

    path
  end
end
