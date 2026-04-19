module Sekrets::Blowfish
  def cipher(mode, key, data)
    cipher =
      begin
        OpenSSL::Cipher.new('bf-cbc').send(mode)
      rescue StandardError => e
        raise if
          @openssl_is_already_monkey_patched ||
          (e.class.name != 'OpenSSL::Cipher::CipherError') ||
          !defined?(OpenSSL::Provider)

        @openssl_is_already_monkey_patched = true
        OpenSSL::Provider.load('legacy')
        OpenSSL::Cipher.new('bf-cbc').send(mode)
      end

    cipher.key = Digest(:SHA256).digest(key.to_s).slice(0, 16)

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
