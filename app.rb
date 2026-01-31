$stdout.sync = true
puts ">>> BOOTING POC..."

require 'bundler/inline'

gemfile(true) do
  source 'https://rubygems.org'
  gem 'sinatra'
  gem 'rackup'
  gem 'puma'
  gem 'restforce'
  gem 'jwt'
  gem 'dotenv'
end

require 'sinatra/base'
require 'dotenv/load'
require 'jwt'
require 'restforce'
require 'securerandom'
require 'uri'
require 'digest'
require 'base64'
require 'net/http'
require 'json'

class SfPocApp < Sinatra::Base
  set :port, ENV['PORT'] || 8080
  set :bind, '0.0.0.0'
  enable :sessions
  set :session_secret, ENV['SECRET_KEY_BASE'] || SecureRandom.hex(64)

  SESSION_MAP = {}

  helpers do
    def base_url
      ENV['BASE_URL'] || ENV['RENDER_EXTERNAL_URL'] || "http://localhost:#{settings.port}"
    end

    def repair_rsa_key(raw_key)
      return nil if raw_key.nil?
      raw_key.gsub('\n', "\n").gsub(/\A"|"\z/, '')
    end

    def fetch_jwt_token(user_data)
      instance_url = user_data[:instance_url]
      username     = user_data[:username]
      
      payload = {
        iss: ENV['SF_CLIENT_ID'],
        sub: username,
        aud: instance_url,
        exp: Time.now.to_i + 300
      }
      
      private_key = OpenSSL::PKey::RSA.new(repair_rsa_key(ENV['SF_PRIVATE_KEY']))
      assertion = JWT.encode(payload, private_key, 'RS256')

      uri = URI("#{instance_url}/services/oauth2/token")
      res = Net::HTTP.post_form(uri, {
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: assertion
      })
      
      data = JSON.parse(res.body)
      raise "JWT Error: #{data['error_description'] || data['error']}" if data['error']
      data['access_token']
    end
  end

  get '/' do
    session[:sf_env] ||= 'production'
    @sf_host = (session[:sf_env] == 'production') ? 'login.salesforce.com' : 'test.salesforce.com'
    
    token = request.cookies['sf_session_token']
    stored_info = SESSION_MAP[token]
    @user_info = (stored_info && stored_info[:env] == session[:sf_env]) ? stored_info : nil

    code_verifier = SecureRandom.hex(32)
    session[:code_verifier] = code_verifier
    code_challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier)).delete('=')
    
    query_params = URI.encode_www_form({
      code_challenge: code_challenge,
      code_challenge_method: 'S256',
      response_type: 'code',
      client_id: ENV['SF_CLIENT_ID'],
      redirect_uri: "#{base_url}/callback",
      scope: 'api refresh_token'
    })
    
    @auth_url = "https://#{@sf_host}/services/oauth2/authorize?#{query_params}"
    erb :index
  end

  get '/callback' do
    current_env = session[:sf_env]
    host = (current_env == 'production') ? 'login.salesforce.com' : 'test.salesforce.com'
    
    begin
      uri = URI("https://#{host}/services/oauth2/token")
      res = Net::HTTP.post_form(uri, {
        grant_type: 'authorization_code',
        code: params[:code],
        client_id: ENV['SF_CLIENT_ID'],
        client_secret: ENV['SF_CLIENT_SECRET'],
        redirect_uri: "#{base_url}/callback",
        code_verifier: session[:code_verifier]
      })
      
      auth_data = JSON.parse(res.body)
      raise "Auth Failed: #{auth_data['error_description']}" if auth_data['error']

      id_uri = URI(auth_data['id'])
      req = Net::HTTP::Get.new(id_uri)
      req['Authorization'] = "Bearer #{auth_data['access_token']}"
      
      id_res = Net::HTTP.start(id_uri.host, id_uri.port, use_ssl: true) { |http| http.request(req) }
      user_data = JSON.parse(id_res.body)
      
      session_token = SecureRandom.hex(16)
      SESSION_MAP[session_token] = { 
        username: user_data['username'], 
        instance_url: auth_data['instance_url'],
        env: current_env
      }
      
      response.set_cookie('sf_session_token', value: session_token, path: '/', expires: Time.now + (3600 * 24 * 7))
      redirect '/'
    rescue => e
      @error = "Authorize Error: #{e.message}"
      erb :index
    end
  end

  post '/fetch_data' do
    token = request.cookies['sf_session_token']
    @user_info = SESSION_MAP[token]

    if @user_info
      begin
        access_token = fetch_jwt_token(@user_info)
        client = Restforce.new(
          oauth_token: access_token,
          instance_url: @user_info[:instance_url],
          api_version: ENV['SF_API_VERSION'] || '65.0'
        )
        @contacts = client.query("SELECT Name FROM Contact LIMIT 10")
      rescue => e
        @error = "JWT Query Failed: #{e.message}"
      end
    end
    erb :index
  end

  get '/toggle' do
    session[:sf_env] = (session[:sf_env] == 'production') ? 'sandbox' : 'production'
    redirect '/'
  end

  get '/clear_session' do
    token = request.cookies['sf_session_token']
    SESSION_MAP.delete(token)
    response.delete_cookie('sf_session_token')
    redirect '/'
  end

  template :index do
    <<~HTML
      <style>
        body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 40px auto; padding: 20px; background: #f4f7f9; color: #16325c; }
        .card { background: white; border: 1px solid #d8dde6; padding: 30px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.07); }
        .btn { background: #0070d2; color: white; padding: 12px 24px; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; font-weight: 600; display: inline-block; }
        .btn-green { background: #2e844a; }
        .err { color: #c23934; background: #fff1f1; padding: 15px; border-radius: 4px; border-left: 4px solid #c23934; margin-bottom: 20px; }
        .switch-container { display: flex; align-items: center; justify-content: space-between; margin-bottom: 25px; background: #eef1f6; padding: 10px 20px; border-radius: 50px; }
        .switch { position: relative; display: inline-block; width: 60px; height: 30px; }
        .switch input { opacity: 0; width: 0; height: 0; }
        .slider { position: absolute; cursor: pointer; top: 0; left: 0; right: 0; bottom: 0; background-color: #0070d2; transition: .4s; border-radius: 34px; }
        .slider:before { position: absolute; content: ""; height: 22px; width: 22px; left: 4px; bottom: 4px; background-color: white; transition: .4s; border-radius: 50%; }
        input:checked + .slider { background-color: #706e6b; }
        input:checked + .slider:before { transform: translateX(30px); }
        .clear-link { display: inline-block; margin-bottom: 15px; font-size: 13px; color: #c23934; text-decoration: underline; }
      </style>

      <h1>Salesforce Ruby Integration PoC</h1>

      <div class="switch-container">
        <span>Target: <strong><%= session[:sf_env].upcase %></strong></span>
        <label class="switch">
          <input type="checkbox" <%= 'checked' if session[:sf_env] == 'sandbox' %> onchange="window.location.href='/toggle'">
          <span class="slider"></span>
        </label>
      </div>

      <% if @error %><div class="err"><strong>Error:</strong> <%= @error %></div><% end %>
      
      <div class="card">
        <% if @user_info %>
          <p style="margin-top:0">Active Session: <strong><%= @user_info[:username] %></strong></p>
          <p style="font-size: 13px; color: #54698d;">Domain: <%= @user_info[:instance_url] %></p>
          <div style="margin-top:15px">
            <a href="/clear_session" class="clear-link">Clear Session</a>
            <br>
            <form action="/fetch_data" method="post">
              <button type="submit" class="btn btn-green">Fetch Contacts</button>
            </form>
          </div>
        <% else %>
          <p style="margin-top:0">No active <strong><%= session[:sf_env].upcase %></strong> session.</p>
          <a href="<%= @auth_url %>" class="btn">Authorize</a>
        <% end %>
      </div>

      <% if @contacts %>
        <div class="card">
          <h3 style="margin-top:0">Contacts</h3>
          <% if @contacts.empty? %>
            <p style="color: #54698d; font-size: 14px;">No contacts found.</p>
          <% else %>
            <ul><% @contacts.each do |c| %><li><%= c.Name %></li><% end %></ul>
          <% end %>
        </div>
      <% end %>
    HTML
  end
end

SfPocApp.run!