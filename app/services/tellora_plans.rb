# frozen_string_literal: true

# Reads config/tellora_plans.yml: Tellora's plans, prices, limits and features.
# Used by the landing page pricing section (and later by billing).
class TelloraPlans
  FILE = Rails.root.join('config', 'tellora_plans.yml')

  class << self
    def data
      return load_file unless Rails.env.production?

      @data ||= load_file
    end

    def plans
      Array(data['plans'])
    end

    def compare
      Array(data['compare'])
    end

    def included
      Array(data['included'])
    end

    def currencies
      data['currencies'] || {}
    end

    def trial_months
      data.fetch('trial_months', 7).to_i
    end

    def billing_months
      data.fetch('billing_months', 6).to_i
    end

    def contact_email
      data['contact_email'].to_s
    end

    # "₹2,999" / "$59"
    def price_label(plan, currency)
      amount = plan.dig('price', currency)
      return nil unless amount

      "#{currencies.dig(currency, 'symbol')}#{ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)}"
    end

    # Monthly equivalent of the 6-month price: "₹500" / "$10"
    def monthly_label(plan, currency)
      amount = plan.dig('price', currency)
      return nil unless amount && billing_months.positive?

      monthly = (amount.to_f / billing_months).round
      "#{currencies.dig(currency, 'symbol')}#{ActiveSupport::NumberHelper.number_to_delimited(monthly)}"
    end

    private

    def load_file
      YAML.safe_load_file(FILE, aliases: false) || {}
    rescue StandardError => e
      Rails.logger.error("[TelloraPlans] could not read #{FILE}: #{e.class} - #{e.message}")
      {}
    end
  end
end
