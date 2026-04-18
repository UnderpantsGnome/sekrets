# sekrets

`sekrets` is a CLI and library for encrypting files that live alongside the rest of your app or repo.

It keeps ciphertext in version control and looks up decryption keys from local key files, environment variables, or an interactive prompt.

## Install

```sh
gem install sekrets
```

In a project:

```ruby
# Gemfile
gem 'sekrets'
```

## CLI

```text
Usage: sekrets <command> [arguments] [options]

Commands:
  write [output] [input]   Encrypt input to a file or stdout
  read [input] [output]    Decrypt input to a file or stdout
  edit <path>              Edit an encrypted file with $SEKRETS_EDITOR or $EDITOR
  recrypt <path>           Re-encrypt a file with a new key
  help                     Show this help
```

Per-command help is available with `sekrets <command> --help`.

## Quick Start

Create an encrypted config file:

```sh
ruby -ryaml -e 'puts({ api_key: 1234 }.to_yaml)' | sekrets write config/settings.yml.enc -k 42
```

Read it back:

```sh
sekrets read config/settings.yml.enc -k 42
```

Edit it in place:

```sh
sekrets edit config/settings.yml.enc -k 42
```

Confirm the file on disk is encrypted:

```sh
cat config/settings.yml.enc
```

Store the key in a project key file so you do not need `-k` every time:

```sh
printf '42\n' > .sekrets.key
printf '.sekrets.key\n' >> .gitignore
```

Then commands can omit the key:

```sh
sekrets read config/settings.yml.enc
sekrets edit config/settings.yml.enc
```

## Library

Read encrypted settings in Ruby:

```ruby
settings = Sekrets.settings_for('./config/settings.yml.enc')
settings.api_key
```

`Sekrets.settings_for` returns a small hash-like wrapper that supports both key access and method-style access for nested hashes.

## Key Lookup

`Sekrets.key_for` uses this precedence order:

1. An explicit `:key` argument.
2. A companion key file next to the encrypted file, such as `config/.settings.yml.enc.key` or `config/.settings.yml.enc.k`.
3. A project key file at `./.sekrets.key` or `Rails.root/.sekrets.key`.
4. The environment variable `SEKRETS_KEY`.
5. A global key file at `~/.sekrets.key`.
6. An interactive prompt when attached to a tty.

Never commit key files.

## Rails

The gem still includes Rails tasks for generating a project key, editor stub, and encrypted config:

```sh
bundle exec rake sekrets:generate:key
bundle exec rake sekrets:generate:editor
bundle exec rake sekrets:generate:config
```

## Capistrano

Capistrano integration is still included. Add this to your `Capfile`:

```ruby
require 'sekrets/capistrano'
```

That task uploads `./.sekrets.key` during deploy so the app can read encrypted files on the target hosts.

## Development

Run tests with:

```sh
bundle exec rake test
```

Useful rake tasks:

```sh
bundle exec rake -T
```
