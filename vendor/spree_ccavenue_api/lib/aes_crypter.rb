class AESCrypter

  INIT_VECTOR = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].pack('C*')

  def self.encrypt(plain_text, key)
    cipher         = aes_cipher
    cipher.encrypt
    secret_key     = Digest::MD5.digest(key)
    cipher.key     = secret_key
    cipher.iv      = INIT_VECTOR
    encrypted_text = cipher.update(plain_text) + cipher.final
    return (encrypted_text.unpack('H*')).first
  end

  def self.decrypt(encrypted_data, key)
    encrypted_data = [encrypted_data].pack('H*')
    cipher         = aes_cipher
    cipher.decrypt
    secret_key     = Digest::MD5.digest(key)
    cipher.key     = secret_key
    cipher.iv      = INIT_VECTOR
    cipher.update(encrypted_data) + cipher.final
  end

  private

  def self.aes_cipher
    OpenSSL::Cipher::AES.new(128, :CBC)
  end

end