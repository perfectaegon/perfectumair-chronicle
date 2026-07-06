#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"
require "yaml"

ROOT = File.expand_path("..", __dir__)
CLI_CONFIG = File.expand_path("~/.render/cli.yaml")

OLD_SERVICE_ID = "srv-d95ouovavr4c73ank0ng"
SERVICE_NAME = "ok-mairr-chronicle"
REPO = "https://github.com/perfectaegon/ok-mairr-chronicle"
BRANCH = "main"
TARGET_URL = "https://#{SERVICE_NAME}.onrender.com"

def load_config
  abort "Render CLI config not found at #{CLI_CONFIG}. Run: render login" unless File.exist?(CLI_CONFIG)
  YAML.load_file(CLI_CONFIG)
end

def api_request(method, path, body: nil)
  config = load_config
  api = config.fetch("api")
  uri = URI.join(api.fetch("host"), path.sub(%r{\A/}, ""))

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"

  klass = Net::HTTP.const_get(method.capitalize)
  request = klass.new(uri)
  request["Authorization"] = "Bearer #{api.fetch("key")}"
  request["Accept"] = "application/json"
  request["Content-Type"] = "application/json" if body
  request.body = JSON.generate(body) if body

  response = http.request(request)
  [response.code.to_i, response.body]
end

def parse_json(body)
  return nil if body.nil? || body.strip.empty?
  JSON.parse(body)
rescue JSON::ParserError
  nil
end

def delete_service(service_id)
  puts "[1/5] Deleting old service #{service_id} (if exists)..."
  code, body = api_request("delete", "/services/#{service_id}")
  case code
  when 204
    puts "  Deleted #{service_id}"
  when 404
    puts "  Old service not found, skipping delete"
  else
    abort "  Delete failed (#{code}): #{body}"
  end
end

def create_service(owner_id, admin_password)
  puts ""
  puts "[2/5] Creating new service #{SERVICE_NAME}..."

  payload = {
    type: "web_service",
    name: SERVICE_NAME,
    ownerId: owner_id,
    repo: REPO,
    branch: BRANCH,
    autoDeploy: "yes",
    envVars: [
      { key: "HOST", value: "0.0.0.0" },
      { key: "FORCE_SSL", value: "1" },
      { key: "SESSION_HOURS", value: "168" },
      { key: "ADMIN_PASSWORD", value: admin_password }
    ],
    serviceDetails: {
      runtime: "ruby",
      plan: "free",
      healthCheckPath: "/",
      envSpecificDetails: {
        buildCommand: "bundle install",
        startCommand: "bundle exec ruby server.rb"
      }
    }
  }

  code, body = api_request("post", "/services", body: payload)
  data = parse_json(body)

  unless code == 201
    abort "  Create failed (#{code}): #{body}"
  end

  service = data.fetch("service", data)
  service_id = service.fetch("id")
  deploy_id = data["deployId"]
  puts "  New service ID: #{service_id}"
  puts "  Initial deploy ID: #{deploy_id}" if deploy_id
  service_id
end

def wait_for_deploy(service_id, max_wait: 600)
  puts ""
  puts "[3/5] Waiting for deploy to succeed..."
  elapsed = 0
  status = "unknown"

  while elapsed < max_wait
    code, body = api_request("get", "/services/#{service_id}/deploys?limit=1")
    data = parse_json(body)

    if code == 200 && data.is_a?(Array) && !data.empty?
      deploy = data.first.fetch("deploy", data.first)
      status = deploy.fetch("status", "unknown")
    end

    puts "  Deploy status: #{status} (#{elapsed}s elapsed)"

    case status
    when "live"
      return "succeeded"
    when "build_failed", "update_failed", "canceled", "pre_deploy_failed"
      abort "  Deploy failed: #{body}"
    end

    sleep 15
    elapsed += 15
  end

  abort "  Timed out waiting for deploy (last status: #{status})"
end

def verify_http
  puts ""
  puts "[4/5] Verifying #{TARGET_URL} returns HTTP 200..."
  uri = URI("#{TARGET_URL}/")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 30
  http.read_timeout = 30

  response = http.get(uri.request_uri)
  code = response.code.to_i
  puts "  HTTP status: #{code}"
  abort "  Health check failed (expected 200)" unless code == 200
  code
end

config = load_config
owner_id = config.fetch("workspace")
admin_password = SecureRandom.alphanumeric(32)

delete_service(OLD_SERVICE_ID)
service_id = create_service(owner_id, admin_password)
deploy_status = wait_for_deploy(service_id)
http_code = verify_http

puts ""
puts "[5/5] Done!"
puts ""
puts "=== RESULTS ==="
puts "Service ID:     #{service_id}"
puts "URL:            #{TARGET_URL}"
puts "ADMIN_PASSWORD: #{admin_password}"
puts "Deploy status:  #{deploy_status}"
puts "HTTP status:    #{http_code}"