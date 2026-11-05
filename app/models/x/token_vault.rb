class X::TokenVault
  class Unavailable < StandardError; end

  def self.key_path
    Pathname.new(ENV["APP_DATA_DIR"] || ENV.fetch("PARCELA_DATA_DIR", Rails.root.join("storage").to_s)).join("x-token.key")
  end

  def self.encrypt(value, purpose: "x_oauth_tokens")
    cipher(create: true).encrypt_and_sign(value, purpose: purpose)
  end

  def self.decrypt(value, purpose: "x_oauth_tokens")
    cipher(create: false).decrypt_and_verify(value, purpose: purpose)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    raise Unavailable, "The saved X credentials cannot be decrypted. Reconnect X."
  end

  def self.cipher(create:)
    path = key_path
    unless path.exist?
      raise Unavailable, "The local X encryption key is missing. Reconnect X." unless create
      FileUtils.mkdir_p(path.dirname)
      begin
        File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.binmode; file.write(SecureRandom.random_bytes(32)) }
      rescue Errno::EEXIST
      end
    end
    raise Unavailable, "The local X encryption key must be readable only by its owner." unless (File.stat(path).mode & 0o077).zero?
    key = File.binread(path)
    raise Unavailable, "The local X encryption key is invalid." unless key.bytesize == 32
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm")
  end
  private_class_method :cipher
end
