module Sekrets::Binstub
  def binstub
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

          if File.size?(key)
            ENV['SEKRETS_KEY'] = IO.binread(key).strip
          end

          exec(Gem.bin_path('sekrets', 'sekrets'), *argv)
      _V_
    )
  end

  def unindent(string)
    indent = string.lines.filter_map { |line| line.index(/[^\s]/) unless line.strip.empty? }.min || 0
    string.gsub(/^[[:blank:]]{#{indent}}/, '')
  end
end
