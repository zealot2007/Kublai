require 'kublai/version'
require 'base64'
require 'net/https'
require 'uri'
require 'json'


module Kublai
  class BTCChina

    attr_accessor :errors, :infos

    def initialize(access='', secret='')
      @access_key = access
      @secret_key = secret
    end

    public

    def get_account_info
      post_data = initial_post_data
      post_data['method'] = 'getAccountInfo'
      post_data['params'] = []
      post_request(post_data)
    end

    def get_deposit_address
      get_account_info['profile']['btc_deposit_address']
    end

    def get_market_depth(limit = 10)
      post_data = initial_post_data
      post_data['method'] = 'getMarketDepth2'
      post_data['params'] = [limit]
      post_request(post_data)["market_depth"]
    end

    def buy(price, amount)
      price = cut_off(price, 5)
      amount = cut_off(amount, 8)
      post_data = initial_post_data
      post_data['method']='buyOrder'
      post_data['params']=[price, amount]
      post_request(post_data)
    end

    def sell(price, amount)
      price = cut_off(price, 5)
      amount = cut_off(amount, 8)
      post_data = initial_post_data
      post_data['method']='sellOrder'
      post_data['params']=[price, amount]
      post_request(post_data)
    end

    def cancel(order_id)
      post_data = initial_post_data
      post_data['method']='cancelOrder'
      post_data['params']=[order_id]
      post_request(post_data)
    end

    def current_price
      ts = ticker
      (ts['buy'].to_f + ts['sell'].to_f) / 2
    end

    def ticker
      get_request("https://data.btcchina.com/data/ticker")
    end

    # params type
    # all | fundbtc | withdrawbtc | fundmoney | withdrawmoney | 
    # refundmoney | buybtc | sellbtc | tradefee
    def get_transactions(type = 'all', limit = 10)
      post_data = initial_post_data
      post_data['method'] = 'getTransactions'
      post_data['params'] = [type, limit]
      post_request(post_data)
    end

    def get_deposits(currency = 'BTC', pendingonly = true)
      post_data = initial_post_data
      post_data['method'] = 'getDeposits'
      post_data['params'] = [currency, pendingonly]
      post_request(post_data)
    end

    def get_withdrawal(id)
      post_data = initial_post_data
      post_data['method'] = 'getWithdrawal'
      post_data['params'] = [id]
      post_request(post_data)
    end

    def get_withdrawals(currency = 'BTC', pendingonly = true)
      post_data = initial_post_data
      post_data['method'] = 'getWithdrawals'
      post_data['params'] = [currency, pendingonly]
      post_request(post_data)
    end

    def request_withdrawal(currency, amount)
      post_data = initial_post_data
      post_data['method'] = 'requestWithdrawal'
      post_data['params'] = [currency, amount]
      post_request(post_data)
    end

    def get_order(id)
      post_data = initial_post_data
      post_data['method'] = 'getOrder'
      post_data['params'] = [id]
      post_request(post_data)
    end

    def get_orders(openonly = true)
      post_data = initial_post_data
      post_data['method'] = 'getOrders'
      post_data['params'] = [openonly]
      post_request(post_data)
    end

    private

    def cut_off(num, exp=0)
      multiplier = 10 ** exp
      cut = ((num * multiplier).floor).to_f/multiplier.to_f
      return cut.floor if cut == cut.floor
      cut
    end

    def sign(params_string)
      signiture = OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('sha1'), @secret_key, params_string)
      'Basic ' + Base64.strict_encode64(@access_key + ':' + signiture)
    end

    def get_request(url)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri.request_uri)
      connection(uri, request)
    end

    def initial_post_data
      post_data = {}
      post_data['tonce']  = (Time.now.to_f * 1000000).to_i.to_s
      post_data
    end

    def post_request(post_data)
      uri = URI.parse("https://api.btcchina.com/api_trade_v1.php")
      payload = params_hash(post_data)
      signiture_string = sign(params_string(payload.clone))
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = payload.to_json
      request.initialize_http_header({"Accept-Encoding" => "identity", 'Json-Rpc-Tonce' => post_data['tonce'], 'Authorization' => signiture_string, 'Content-Type' => 'application/json', "User-Agent" => "Kublai"})
      connection(uri, request)
    end

    def connection(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      # http.set_debug_output($stderr)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.read_timeout = 20
      http.open_timeout = 5
      response(http.request(request))
    end

    def response(response_data)
      self.errors, self.infos = {}, {}
      if response_data.code == '200' && response_data.body['result']
        self.infos = JSON.parse(response_data.body)
        self.infos['result']
      elsif response_data.code == '200' && response_data.body['ticker']
        self.infos = JSON.parse(response_data.body)
        self.infos['ticker']
      elsif response_data.code == '200' && response_data.body['error']
        error = JSON.parse(response_data.body)
        self.errors = {
          code: error['error']['code'], 
          message: error['error']['message']
        }
        warn("Error Code: #{error['error']['code']}")
        warn("Error Message: #{error['error']['message']}")
        false
      else
        self.errors = {
          code: response_data.code, 
          message: response_data.message
        }
        warn("Error Code: #{response_data.code}")
        warn("Error Message: #{response_data.message}")
        warn("check your accesskey/privatekey") if response_data.code == '401'
        false
      end
    end

    def params_string(post_data)
      post_data['params'] = post_data['params'].join(',')
      str = params_hash(post_data).collect{|k, v| "#{k}=#{v}"} * '&'

      str.gsub("[\[\] ]", "").gsub("'", '').gsub("true", '1').gsub("false", '')
    end

    def params_hash(post_data)
      post_data['accesskey'] = @access_key
      post_data['requestmethod'] = 'post'
      post_data['id'] = post_data['tonce'] unless post_data.keys.include?('id')
      fields=['tonce','accesskey','requestmethod','id','method','params']
      ordered_data = {}
      fields.each do |field|
        ordered_data[field] = post_data[field]
      end
      ordered_data
    end
  end
end
