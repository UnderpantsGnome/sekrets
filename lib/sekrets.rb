require 'erb'
require 'fileutils'
require 'openssl'
require 'pathname'
require 'securerandom'
require 'tmpdir'
require 'yaml'
require_relative 'sekrets/version'

class Sekrets < String
  class << self
    attr_writer :env, :editor, :root, :project_key, :global_key, :summary, :description

    def version
      VERSION
    end

    def env
      @env || 'SEKRETS_KEY'
    end

    def editor
      @editor || ENV['SEKRETS_EDITOR'] || ENV['EDITOR'] || 'vim'
    end

    def root
      return @root if defined?(@root) && !@root.nil?

      defined?(Rails.root) ? Rails.root : '.'
    end

    def project_key
      @project_key || File.join(root, '.sekrets.key')
    end

    def global_key
      @global_key || File.join(File.expand_path('~'), '.sekrets.key')
    end

    def summary
      @summary || 'securely manage encrypted files and settings'
    end

    def description
      @description ||
        "sekrets is a command line tool and library used to securely manage encrypted files and settings in your rails' applications and git repositories."
    end
  end
end

require_relative 'sekrets/settings'
require_relative 'sekrets/keys'
require_relative 'sekrets/files'
require_relative 'sekrets/console'
require_relative 'sekrets/tempfiles'
require_relative 'sekrets/binstub'
require_relative 'sekrets/blowfish'

Sekrets.extend(Sekrets::Keys)
Sekrets.extend(Sekrets::Files)
Sekrets.extend(Sekrets::Console)
Sekrets.extend(Sekrets::Tempfiles)
Sekrets.extend(Sekrets::Binstub)
Sekrets.extend(Sekrets::Blowfish)

Sekret = Sekrets

require_relative 'sekrets/engine' if defined?(Rails)
