#!/usr/bin/env ruby
# frozen_string_literal: true

require "webrick"
require "json"
require "fileutils"
require "securerandom"
require "time"
require "digest"
require "open3"

ROOT = File.expand_path(__dir__)
PUBLIC_DIR = File.join(ROOT, "public")
UPLOAD_DIR = File.join(ROOT, "data", "uploads")
POSTS_FILE = File.join(ROOT, "data", "posts.json")
SESSIONS_FILE = File.join(ROOT, "data", "sessions.json")
PORT = Integer(ENV.fetch("PORT", 4568))
HOST = ENV.fetch("HOST", "0.0.0.0")
ADMIN_PASSWORD = ENV.fetch("ADMIN_PASSWORD", "chronicle2026")
SESSION_HOURS = Integer(ENV.fetch("SESSION_HOURS", 72))
MAX_IMAGE_BYTES = 15 * 1024 * 1024
MAX_VIDEO_BYTES = 100 * 1024 * 1024

WEB_IMAGE_TYPES = {
  "image/jpeg" => ".jpg",
  "image/png" => ".png",
  "image/webp" => ".webp",
  "image/gif" => ".gif"
}.freeze

CONVERTIBLE_IMAGE_TYPES = {
  "image/heic" => ".heic",
  "image/heif" => ".heif",
  "image/avif" => ".avif",
  "image/tiff" => ".tiff",
  "image/bmp" => ".bmp"
}.freeze

PHOTO_TYPES = WEB_IMAGE_TYPES.merge(CONVERTIBLE_IMAGE_TYPES).freeze

VIDEO_TYPES = {
  "video/mp4" => ".mp4",
  "video/webm" => ".webm",
  "video/quicktime" => ".mov"
}.freeze

EXTENSION_FOR_MIME = (PHOTO_TYPES.merge(VIDEO_TYPES)).invert.freeze

MIME_TYPES = {
  ".jpg" => "image/jpeg",
  ".jpeg" => "image/jpeg",
  ".png" => "image/png",
  ".webp" => "image/webp",
  ".gif" => "image/gif",
  ".heic" => "image/heic",
  ".heif" => "image/heif",
  ".avif" => "image/avif",
  ".tif" => "image/tiff",
  ".tiff" => "image/tiff",
  ".bmp" => "image/bmp",
  ".mp4" => "video/mp4",
  ".webm" => "video/webm",
  ".mov" => "video/quicktime",
  ".html" => "text/html",
  ".css" => "text/css",
  ".js" => "application/javascript"
}.freeze

FileUtils.mkdir_p(UPLOAD_DIR)
FileUtils.mkdir_p(File.dirname(POSTS_FILE))

def load_json(path, fallback)
  return fallback unless File.exist?(path)

  JSON.parse(File.read(path))
rescue JSON::ParserError
  fallback
end

def save_json(path, payload)
  File.write(path, JSON.pretty_generate(payload))
end

def load_posts
  load_json(POSTS_FILE, [])
end

def save_posts(posts)
  save_json(POSTS_FILE, posts)
end

def load_sessions
  load_json(SESSIONS_FILE, {})
end

def save_sessions(sessions)
  save_json(SESSIONS_FILE, sessions)
end

def json_response(res, status, payload)
  res.status = status
  res["Content-Type"] = "application/json; charset=utf-8"
  res.body = JSON.generate(payload)
end

def read_body(req)
  body = req.body
  return "" if body.nil?

  body.respond_to?(:read) ? body.read : body.to_s
end

def mime_for(path)
  MIME_TYPES[File.extname(path).downcase] || "application/octet-stream"
end

def sanitize_filename(name)
  File.basename(name.to_s).gsub(/[^\w.\-]/, "_")
end

def form_text(field)
  return "" if field.nil?
  return field.to_s unless field.is_a?(WEBrick::HTTPUtils::FormData)

  chunks = []
  field.each_data { |data| chunks << data.to_s }
  chunks.join
end

def form_file?(field)
  field.is_a?(WEBrick::HTTPUtils::FormData) && !field.filename.to_s.empty?
end

def form_file_bytes(field)
  chunks = []
  field.each_data { |data| chunks << data.to_s }
  chunks.join
end

def mime_for_upload(filename)
  MIME_TYPES[File.extname(filename.to_s).downcase]
end

def sniff_photo_mime(file_bytes)
  return "image/jpeg" if file_bytes.start_with?("\xFF\xD8\xFF")
  return "image/png" if file_bytes.start_with?("\x89PNG\r\n\x1a\n")
  return "image/gif" if file_bytes.start_with?("GIF87a", "GIF89a")
  if file_bytes.bytesize >= 12 && file_bytes[0..3] == "RIFF" && file_bytes[8..11] == "WEBP"
    return "image/webp"
  end
  return "image/bmp" if file_bytes.start_with?("BM")
  return "image/tiff" if file_bytes.start_with?("\x49\x49\x2A\x00", "\x4D\x4D\x00\x2A")

  if file_bytes.bytesize >= 12 && file_bytes[4..7] == "ftyp"
    brand = file_bytes[8..11]
    return "image/heic" if %w[heic heix hevc hevx hev1].include?(brand)
    return "image/heif" if %w[mif1 msf1].include?(brand)
    return "image/avif" if brand == "avif" || file_bytes.include?("avif")
  end

  nil
end

def detect_photo_mime(file_bytes, filename)
  mime = mime_for_upload(filename)
  return mime if mime && PHOTO_TYPES.key?(mime)

  sniff_photo_mime(file_bytes)
end

def convert_image_to_jpeg(input_path, output_path)
  [
    ["magick", input_path, "-auto-orient", "-quality", "90", output_path],
    ["convert", input_path, "-auto-orient", "-quality", "90", output_path]
  ].each do |command|
    _stdout, _stderr, status = Open3.capture3(*command)
    next unless status.success?
    next unless File.exist?(output_path) && File.size(output_path).positive?

    return true
  end

  false
end

def parse_json_body(req)
  JSON.parse(read_body(req))
rescue JSON::ParserError
  nil
end

def parse_multipart(req)
  content_type = req["Content-Type"].to_s
  return nil unless content_type.start_with?("multipart/form-data")

  boundary = content_type[/boundary=(.+?)(?:;|\z)/, 1]
  return nil unless boundary

  WEBrick::HTTPUtils.parse_form_data(read_body(req), boundary)
end

def cookie_value(req, name)
  header = req["Cookie"].to_s
  header.split(";").each do |part|
    key, value = part.strip.split("=", 2)
    return value if key == name
  end
  nil
end

def set_cookie(res, name, value, max_age: nil)
  cookie = WEBrick::Cookie.new(name, value)
  cookie.path = "/"
  cookie.max_age = max_age if max_age
  cookie.secure = true if ENV["FORCE_SSL"] == "1"
  res.cookies << cookie
end

def clear_cookie(res, name)
  cookie = WEBrick::Cookie.new(name, "")
  cookie.path = "/"
  cookie.max_age = 0
  res.cookies << cookie
end

def clean_sessions!
  sessions = load_sessions
  cutoff = Time.now.utc - (SESSION_HOURS * 3600)
  sessions.delete_if do |_token, meta|
    Time.parse(meta["created_at"]) < cutoff
  rescue ArgumentError
    true
  end
  save_sessions(sessions)
  sessions
end

def create_session!
  sessions = clean_sessions!
  token = SecureRandom.hex(32)
  sessions[token] = { "created_at" => Time.now.utc.iso8601 }
  save_sessions(sessions)
  token
end

def authenticated?(req)
  token = cookie_value(req, "admin_session")
  return false if token.to_s.empty?

  sessions = clean_sessions!
  sessions.key?(token)
end

def require_admin!(req, res)
  return true if authenticated?(req)

  json_response(res, 401, { error: "Admin login required" })
  false
end

def serve_static(res, relative_path, content_type)
  path = File.join(PUBLIC_DIR, relative_path)
  unless File.exist?(path)
    res.status = 404
    res.body = "Not found"
    return false
  end

  res["Content-Type"] = content_type
  res.body = File.read(path)
  true
end

def sorted_posts(posts)
  posts.sort_by { |post| post["published_at"] }.reverse
end

def store_photo(file_bytes, original_name)
  mime = detect_photo_mime(file_bytes, original_name)
  raise "Unsupported photo format" unless mime && PHOTO_TYPES.key?(mime)

  id = SecureRandom.uuid

  if WEB_IMAGE_TYPES[mime]
    extension = WEB_IMAGE_TYPES[mime]
    stored_name = "#{id}#{extension}"
    stored_path = File.join(UPLOAD_DIR, stored_name)
    File.binwrite(stored_path, file_bytes)

    return {
      "filename" => stored_name,
      "original_name" => original_name,
      "size" => file_bytes.bytesize,
      "mime" => mime
    }
  end

  extension = CONVERTIBLE_IMAGE_TYPES[mime]
  temp_path = File.join(UPLOAD_DIR, "#{id}_tmp#{extension}")
  stored_name = "#{id}.jpg"
  stored_path = File.join(UPLOAD_DIR, stored_name)

  File.binwrite(temp_path, file_bytes)
  unless convert_image_to_jpeg(temp_path, stored_path)
    File.delete(temp_path) if File.exist?(temp_path)
    raise "Could not process photo format. Try JPG or PNG, or re-upload from your phone."
  end
  File.delete(temp_path)

  {
    "filename" => stored_name,
    "original_name" => original_name,
    "size" => File.size(stored_path),
    "mime" => "image/jpeg"
  }
end

def store_media(file, type)
  file_bytes = form_file_bytes(file)
  max_bytes = type == "photo" ? MAX_IMAGE_BYTES : MAX_VIDEO_BYTES
  label = type == "photo" ? "Photo" : "Video"

  raise "#{label} must be #{(max_bytes / (1024 * 1024))} MB or smaller" if file_bytes.bytesize > max_bytes

  original_name = sanitize_filename(file.filename)

  if type == "photo"
    return store_photo(file_bytes, original_name)
  end

  mime = mime_for_upload(original_name)
  extension = VIDEO_TYPES[mime]
  raise "Unsupported #{label.downcase} format" unless extension

  id = SecureRandom.uuid
  stored_name = "#{id}#{extension}"
  stored_path = File.join(UPLOAD_DIR, stored_name)
  File.binwrite(stored_path, file_bytes)

  {
    "filename" => stored_name,
    "original_name" => original_name,
    "size" => file_bytes.bytesize,
    "mime" => mime
  }
end

def delete_post(post_id)
  posts = load_posts
  post = posts.find { |entry| entry["id"] == post_id }
  return false unless post

  if post["filename"]
    path = File.join(UPLOAD_DIR, post["filename"])
    File.delete(path) if File.exist?(path)
  end

  posts.reject! { |entry| entry["id"] == post_id }
  save_posts(posts)
  true
end

server = WEBrick::HTTPServer.new(
  Port: PORT,
  BindAddress: HOST,
  AccessLog: [],
  Logger: WEBrick::Log.new($stderr, WEBrick::BasicLog::WARN)
)

server.mount_proc "/api/posts" do |req, res|
  path = req.path.to_s
  post_id = path.delete_prefix("/api/posts/").delete_prefix("/api/posts").split("/").reject(&:empty?).first

  if post_id && !post_id.empty?
    if req.request_method == "GET"
      post = load_posts.find { |entry| entry["id"] == post_id }
      if post
        json_response(res, 200, { post: post })
      else
        json_response(res, 404, { error: "Post not found" })
      end
      next
    end

    json_response(res, 405, { error: "Method not allowed" })
    next
  end

  if req.request_method == "GET"
    posts = sorted_posts(load_posts)
    type_filter = req.query["type"]
    posts = posts.select { |p| p["type"] == type_filter } if type_filter && !type_filter.empty?
    json_response(res, 200, { posts: posts })
    next
  end

  json_response(res, 405, { error: "Method not allowed" })
end

server.mount_proc "/admin/api/login" do |req, res|
  unless req.request_method == "POST"
    json_response(res, 405, { error: "Method not allowed" })
    next
  end

  payload = parse_json_body(req)
  password = payload ? payload["password"].to_s : ""

  if password.empty? || password != ADMIN_PASSWORD
    json_response(res, 401, { error: "Incorrect password" })
    next
  end

  token = create_session!
  set_cookie(res, "admin_session", token, max_age: SESSION_HOURS * 3600)
  json_response(res, 200, { ok: true })
end

server.mount_proc "/admin/api/logout" do |req, res|
  unless req.request_method == "POST"
    json_response(res, 405, { error: "Method not allowed" })
    next
  end

  token = cookie_value(req, "admin_session")
  if token
    sessions = load_sessions
    sessions.delete(token)
    save_sessions(sessions)
  end

  clear_cookie(res, "admin_session")
  json_response(res, 200, { ok: true })
end

server.mount_proc "/admin/api/session" do |req, res|
  json_response(res, 200, { authenticated: authenticated?(req) })
end

server.mount_proc "/admin/api/posts" do |req, res|
  next unless require_admin!(req, res)

  path = req.path.to_s
  post_id = path.delete_prefix("/admin/api/posts/").delete_prefix("/admin/api/posts").split("/").reject(&:empty?).first

  if post_id && !post_id.empty?
    if req.request_method == "DELETE"
      if delete_post(post_id)
        json_response(res, 200, { ok: true })
      else
        json_response(res, 404, { error: "Post not found" })
      end
      next
    end

    json_response(res, 405, { error: "Method not allowed" })
    next
  end

  if req.request_method == "GET"
    json_response(res, 200, { posts: sorted_posts(load_posts) })
    next
  end

  json_response(res, 405, { error: "Method not allowed" })
end

server.mount_proc "/admin/api/article" do |req, res|
  next unless require_admin!(req, res)

  unless req.request_method == "POST"
    json_response(res, 405, { error: "Method not allowed" })
    next
  end

  payload = parse_json_body(req)
  unless payload
    json_response(res, 400, { error: "Invalid JSON body" })
    next
  end

  title = payload["title"].to_s.strip[0, 200]
  body = payload["body"].to_s.strip[0, 50_000]
  excerpt = payload["excerpt"].to_s.strip[0, 400]

  if title.empty? || body.empty?
    json_response(res, 400, { error: "Title and body are required" })
    next
  end

  post = {
    "id" => SecureRandom.uuid,
    "type" => "article",
    "title" => title,
    "body" => body,
    "excerpt" => excerpt.empty? ? body[0, 200] : excerpt,
    "published_at" => Time.now.utc.iso8601
  }

  posts = load_posts
  posts << post
  save_posts(posts)
  json_response(res, 201, { post: post })
end

server.mount_proc "/admin/api/upload" do |req, res|
  next unless require_admin!(req, res)

  unless req.request_method == "POST"
    json_response(res, 405, { error: "Method not allowed" })
    next
  end

  form = parse_multipart(req)
  unless form
    json_response(res, 400, { error: "Expected multipart form upload" })
    next
  end

  media_type = form_text(form["type"]).strip
  unless %w[photo video].include?(media_type)
    json_response(res, 400, { error: "Type must be photo or video" })
    next
  end

  file = form["file"]
  title = form_text(form["title"]).strip[0, 200]
  caption = form_text(form["caption"]).strip[0, 500]

  unless form_file?(file)
    json_response(res, 400, { error: "Please choose a file to upload" })
    next
  end

  begin
    media = store_media(file, media_type)
    post = {
      "id" => SecureRandom.uuid,
      "type" => media_type,
      "title" => title.empty? ? (caption.empty? ? "Untitled capture" : caption[0, 80]) : title,
      "caption" => caption,
      "filename" => media["filename"],
      "original_name" => media["original_name"],
      "size" => media["size"],
      "mime" => media["mime"],
      "published_at" => Time.now.utc.iso8601
    }

    posts = load_posts
    posts << post
    save_posts(posts)
    json_response(res, 201, { post: post })
  rescue StandardError => e
    json_response(res, 400, { error: e.message })
  end
end

server.mount_proc "/uploads/" do |req, res|
  filename = sanitize_filename(req.path.to_s.delete_prefix("/uploads/"))
  path = File.join(UPLOAD_DIR, filename)

  unless File.exist?(path) && path.start_with?(UPLOAD_DIR)
    res.status = 404
    res.body = "Not found"
    next
  end

  res["Content-Type"] = mime_for(path)
  res["Cache-Control"] = "public, max-age=31536000, immutable"
  res.body = File.binread(path)
end

server.mount_proc "/admin" do |req, res|
  if req.path == "/admin" || req.path == "/admin/"
    serve_static(res, "admin.html", "text/html; charset=utf-8")
    next
  end

  asset = req.path.delete_prefix("/admin/")
  case asset
  when "admin.css"
    serve_static(res, "admin.css", "text/css; charset=utf-8")
  when "admin.js"
    serve_static(res, "admin.js", "application/javascript; charset=utf-8")
  else
    res.status = 404
    res.body = "Not found"
  end
end

server.mount_proc "/" do |req, res|
  case req.path
  when "/", "/index.html"
    serve_static(res, "index.html", "text/html; charset=utf-8")
  when "/post.html"
    serve_static(res, "post.html", "text/html; charset=utf-8")
  when "/styles.css"
    serve_static(res, "styles.css", "text/css; charset=utf-8")
  when "/app.js"
    serve_static(res, "app.js", "application/javascript; charset=utf-8")
  when "/post.js"
    serve_static(res, "post.js", "application/javascript; charset=utf-8")
  else
    res.status = 404
    res.body = "Not found"
  end
end

trap("INT") { server.shutdown }

puts "The ok.mairr Chronicle running at http://#{HOST}:#{PORT}"
puts "Editor's desk (admin): http://#{HOST}:#{PORT}/admin"
server.start