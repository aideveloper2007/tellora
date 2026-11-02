class User < ApplicationRecord
  has_secure_password
  
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :surname, presence: true
  validates :password, length: { minimum: 6 }, if: -> { new_record? || !password.nil? }
  
  before_save :downcase_email
  
  private
  
  def downcase_email
    self.email = email.downcase.strip if email.present?
  end
end