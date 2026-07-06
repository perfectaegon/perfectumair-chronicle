# frozen_string_literal: true

require "net/http"
require "uri"
require "base64"
require "json"

class GithubArchive
  API_HOST = "api.github.com"

  def initialize(token:, repo:, branch: "main")
    @token = token.to_s.strip
    @repo = repo
    @branch = branch
    @sha_cache = {}
  end

  def enabled?
    !@token.empty?
  end

  def push(path, bytes, message)
    return unless enabled?

    payload = {
      "message" => message,
      "content" => Base64.strict_encode64(bytes),
      "branch" => @branch
    }

    sha = file_sha(path)
    payload["sha"] = sha if sha

    api_request(:put, contents_path(path), payload)
    @sha_cache.delete(path)
    true
  end

  def delete(path, message)
    return unless enabled?

    sha = file_sha(path)
    return true unless sha

    api_request(:delete, contents_path(path), {
      "message" => message,
      "sha" => sha,
      "branch" => @branch
    })
    @sha_cache.delete(path)
    true
  end

  private

  def contents_path(path)
    encoded = path.split("/").map { |part| URI.encode_www_form_component(part) }.join("/")
    "/repos/#{@repo}/contents/#{encoded}"
  end

  def file_sha(path)
    return @sha_cache[path] if @sha_cache.key?(path)

    response = api_request(:get, contents_path(path))
    sha = response.is_a?(Hash) ? response["sha"] : nil
    @sha_cache[path] = sha if sha
    sha
  rescue StandardError
    nil
  end

  def api_request(method, path, body = nil)
    uri = URI::HTTPS.build(host: API_HOST, path: path)
    request =
      case method
      when :get then Net::HTTP::Get.new(uri)
      when :put then Net::HTTP::Put.new(uri)
      when :delete then Net::HTTP::Delete.new(uri)
      else
        raise ArgumentError, "Unsupported method: #{method}"
      end

    request["Authorization"] = "Bearer #{@token}"
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body) if body

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    return nil if response.code == "404"

    unless response.is_a?(Net::HTTPSuccess)
      raise "GitHub archive failed (#{response.code}): #{response.body}"
    end

    return nil if response.body.to_s.strip.empty?

    JSON.parse(response.body)
  end
end