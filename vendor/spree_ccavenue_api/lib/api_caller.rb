require 'rack'
require 'aes_crypter'

module CcavenueApi
  class ApiCaller

    VALIDATION_SUCCESS_MSG = 'Providing Reference_No/Order No is mandatory'

    def self.refund(order, payment_method, tracking_id)
      json_params = json_params_for_encryption(order, payment_method, tracking_id) # Params required for encryption
      encryption_key = payment_method.preferred_encryption_key

      url = api_url(payment_method)
      params = {
          request_type: 'JSON',
          command: 'refundOrder',
          access_code: payment_method.preferred_access_code,
          enc_request: AESCrypter.encrypt(json_params.to_s, encryption_key)
      }

      decrypted_response(url, params, encryption_key, !payment_method.preferred_test_mode)
    end

    def self.cancel(order, payment_method, tracking_id)
      encryption_key = payment_method.preferred_encryption_key
      url = api_url(payment_method)

      order_as_list = [{reference_no: tracking_id, amount: order.total.to_s}]
      json_params_for_encryption = {'order_List' => order_as_list}.to_json.to_s
      params = {
          request_type: 'JSON',
          command: 'cancelOrder',
          access_code: payment_method.preferred_access_code,
          enc_request: AESCrypter.encrypt(json_params_for_encryption, encryption_key)
      }
      decrypted_response(url, params, encryption_key, !payment_method.preferred_test_mode)
    end

    def self.status(payment_method, order, tracking_id)
      encryption_key = payment_method.preferred_encryption_key
      url = api_url(payment_method)
      order_no = order.nil? ? '' : order.number
      params = {
          request_type: 'JSON',
          command: 'orderStatusTracker',
          access_code: payment_method.preferred_access_code,
          enc_request: AESCrypter.encrypt({reference_no: tracking_id.to_s, order_no: order_no}.to_json.to_s, encryption_key)
      }
      decrypted_response(url, params, encryption_key, !payment_method.preferred_test_mode)
    end

    private

    def self.decrypted_response(url, params, encryption_key, verify_ssl=nil)
      response = nil
      begin
        Rails.logger.info "Params sent to #{url}: #{params.inspect}\nverify_ssl: '#{verify_ssl}'"
        response = RestClient::Request.execute(method: :post, url: url, payload: params,
                                headers: {'Accept' => 'application/json', :accept_encoding => 'gzip, deflate'},
                                verify_ssl: verify_ssl)
      rescue RestClient::RequestTimeout, RestClient::Exception, RuntimeError => error
        return ApiResponse.new({status: 1, enc_response: error.message}, encryption_key)
      end
      decrypt_response(response, encryption_key)
    end

    def self.json_params_for_encryption(order, payment_method, tracking_id)
      {
          reference_no: tracking_id, # order.id, # not sure if ccavenue_order_number should be sent instead (because of error: 'Reference no should be numeric and greater than zero')
          refund_amount: order.total.to_s,
          refund_ref_no: payment_method.preferred_merchant_id
      }.to_json
    end

    def self.decrypt_response(response, encryption_key)
      Rails.logger.info "Response from API: #{response.body.inspect}"
      params_s = response.body.to_s
      params = Rack::Utils.parse_query(params_s)
      ApiResponse.new(params, encryption_key)
    end

    def self.api_url(payment_method)
      payment_method.preferred_test_mode ? 'https://180.179.175.17/apis/servlet/DoWebTrans' : 'https://login.ccavenue.com/apis/servlet/DoWebTrans'
    end

    def self.signup_url(payment_method)
      payment_method.preferred_test_mode ? 'https://180.179.175.17/web/registration.do?command=navigateSchemeForm' : 'https://login.ccavenue.com/web/registration.do?command=navigateSchemeForm'
    end

    def self.validate_creds(payment_method, access_code, encryption_key)
      url = api_url(payment_method)
      params = {
          request_type: 'JSON',
          command: 'orderStatusTracker',
          access_code: access_code,
          enc_request: AESCrypter.encrypt({reference_no: '', order_no: ''}.to_json.to_s, encryption_key)
      }
      reason = (decrypted_response(url, params, encryption_key, !payment_method.preferred_test_mode)).reason
      unless reason.include?(VALIDATION_SUCCESS_MSG)
        Rails.logger.error "CCAve cred validation error: #{reason}"
        return reason
      end
      nil
    rescue => e
      Rails.logger.error e.message
      return e.message
    end

    class ApiResponse
      attr_accessor :status, :reason, :refund_status, :order_status, :success_count

      def initialize(params, encryption_key)
        self.status = params['status']
        if success?
          initialize_from_decrypted_response(encryption_key, params)
        else
          self.reason = params['enc_response']
        end
      end

      def initialize_from_decrypted_response(encryption_key, params)
        enc_response = params['enc_response'].gsub('\r\n', '').strip
        json_params = ActiveSupport::JSON.decode(AESCrypter.decrypt(enc_response, encryption_key))
        Rails.logger.info "Decrypted json params: #{json_params}"
        if json_params['Refund_Order_Result']
          self.refund_status = json_params['Refund_Order_Result']['refund_status']
          self.reason = json_params['Refund_Order_Result']['reason'] # Only present for failed requests
        elsif json_params['Order_Status_Result']
          self.reason = json_params['Order_Status_Result']['error_desc'] # Only present for failed requests
          self.order_status = json_params['Order_Status_Result']['error_desc'] # Only present for failed requests
        elsif json_params['Order_Result']
          self.success_count = json_params['Order_Result']['success_count']
          self.reason = json_params['Order_Result']['failed_List']['failed_order'].first['reason'] rescue 'reason not found'
        else
          raise ArgumentError.new 'Unknown response type'
        end
      end

      def success?
        self.status.to_s == '0'
      end

      def authorization
        "#{self.reason} #{self.refund_status}"
      end
    end

  end
end
