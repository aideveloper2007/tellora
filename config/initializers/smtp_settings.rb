Rails.application.configure do
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: 'email-smtp.eu-central-1.amazonaws.com',
    port: 587,
    domain: 'senco.nu',
    user_name: 'AKIA5FYBBU2U6FJOQD4H',
    password: 'BJ8i9wn1/qkJ92t6z1qeApbQO0lQzuA+FYTLS6lm389M',
    authentication: :login,
    enable_starttls_auto: true
  }
  
  # Enable email delivery in production
  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
end