module Sekrets::Keys
  def extract_options!(args)
    args.last.is_a?(Hash) ? args.pop.dup : {}
  end

  def list_of_strings(*values)
    values.flatten.compact.map(&:to_s).reject(&:empty?)
  end

  def key_for(*args)
    options = extract_options!(args)
    path = args.shift || options[:path]

    return options[:key] if options.key?(:key)

    path = path_for(path)

    if path
      dirname, basename = File.split(path)

      keyfiles =
        list_of_strings(
          %i[keyfile keyfiles].map { |key| options[key] },
          %W[#{dirname}/.#{basename}.key #{dirname}/.#{basename}.k]
        )

      keyfiles.each do |file|
        return IO.binread(file).strip if File.size?(file)
      end
    end

    return IO.binread(project_key).strip if project_key && File.size?(project_key)

    env_key = (options[:env] || env).to_s
    return ENV[env_key] if ENV.key?(env_key)

    return IO.binread(global_key).strip if global_key && File.size?(global_key)
    return ask(path) if options[:prompt] != false && console?

    nil
  end

  def key_for!(*args, &block)
    key = key_for(*args, &block)
    raise(ArgumentError, 'no key!') unless key

    key
  end
end
