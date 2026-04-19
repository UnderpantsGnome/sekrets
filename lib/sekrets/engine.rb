class Sekrets::Engine < Rails::Engine
  engine_name :sekrets

  rake_tasks do
    namespace :sekrets do
      namespace :generate do
        desc 'generate a .sekrets.key'
        task :key do
          keyfile = File.join(Rails.root, '.sekrets.key')
          abort("#{keyfile} exists!") if File.exist?(keyfile)
          key = SecureRandom.hex
          File.open(keyfile, 'wb') { |fd| fd.puts(key) }

          begin
            gitignore = File.join(Rails.root, '.gitignore')
            buf = IO.read(gitignore)

            unless /\.sekrets\.key/.match?(buf)
              File.open(gitignore, 'a+') do |fd|
                fd.puts
                fd.puts '.sekrets.key'
                fd.puts
              end
            end
          rescue StandardError
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
          abort("run 'rake sekrets:generate:key' first") unless File.exist?(keyfile)
          key = IO.binread(keyfile).strip

          editor = File.join(Rails.root, 'sekrets', 'editor')
          ciphertext = File.join(Rails.root, 'sekrets', 'ciphertext')

          unless File.size?(editor)
            FileUtils.mkdir_p(File.dirname(editor))
            File.binwrite(editor, Sekrets.binstub)
            File.chmod(0o755, editor)
            puts "created #{editor}"
          end

          unless File.size?(ciphertext)
            content = "# store sensitive information like credit cards, ssh keys, and passwords here\n\n\n"
            Sekrets.write(ciphertext, content, key: key)
            puts "created #{ciphertext}"
          end

          puts 'run ./sekrets/editor to edit ./sekrets/ciphertext'
        end

        desc 'generate a secure config for application sekrets'
        task :config do
          keyfile = File.join(Rails.root, '.sekrets.key')
          abort("run 'rake sekrets:generate:key' first") unless File.exist?(keyfile)
          key = IO.binread(keyfile).strip

          config = File.join(Rails.root, 'config', 'sekrets.yml.enc')
          unless File.size?(config)
            FileUtils.mkdir_p(File.dirname(config))
            content = { 'api_key' => 42 }.to_yaml
            Sekrets.write(config, content, key: key)
            puts "created #{config}"
          end

          initializer = File.join(Rails.root, 'config', 'initializers', 'sekrets.rb')
          unless File.size?(initializer)
            FileUtils.mkdir_p(File.dirname(initializer))
            File.open(initializer, 'wb') do |fd|
              code = <<~RUBY

                config = File.join(Rails.root, 'config', 'sekrets.yml.enc')
                key = File.join(Rails.root, '.sekrets.key')

                if File.exist?(config)
                  if File.exist?(key)
                    SEKRETS = Sekrets.settings_for(config)
                  else
                    SEKRETS = Sekrets::Settings.new
                    warn "missing \#{key}!"
                  end
                end

              RUBY
              fd.puts(code)
            end
            puts "created #{initializer}"
          end
        end
      end
    end
  end
end
