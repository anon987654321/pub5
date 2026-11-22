#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "optparse"
require "set"
require "uri"
require_relative "../lib/trace/dmesg"
require_relative "../lib/io/ssrf_guard"

options = { url: "https://brgen.no/", limit: 250, timeout: 10 }
OptionParser.new do |opts|
  opts.on("--url URL") { |v| options[:url] = v }
  opts.on("--limit N", Integer) { |v| options[:limit] = v }
  opts.on("--timeout SEC", Integer) { |v| options[:timeout] = v }
end.parse!

origin = URI(options[:url])
queue = [origin]
seen = Set.new
findings = []

while (uri = queue.shift) && seen.length < options[:limit]
  next unless uri.host == origin.host
  key = uri.to_s
  next if seen.include?(key)

  seen << key
  response = begin
    raise URI::InvalidURIError, "census origin must use HTTP/80 or HTTPS/443" unless Master::Io::SsrfGuard.valid_http_uri?(uri)

    Master::Io::SsrfGuard.request(
      uri, Net::HTTP::Get.new(uri.request_uri),
      max_bytes: 2_000_000, timeout: options[:timeout]
    )
  rescue StandardError => error
    findings << { url: uri.to_s, error: "#{error.class}: #{error.message}" }
    next
  end

  findings << { url: uri.to_s, status: response.code.to_i } unless response.code.to_i.between?(200, 399)
  next unless response["content-type"].to_s.include?("text/html")

  body = response.body.to_s
  body.scan(/<a\b[^>]*href\s*=\s*["']([^"']+)["']/i).flatten.each do |href|
    if href.strip == "#"
      findings << { url: uri.to_s, rule: "href_hash" }
      next
    end
    next if href.match?(/\A(?:mailto|tel|javascript):/i)

    child = URI.join(uri.to_s, href).tap { |u| u.fragment = nil } rescue nil
    queue << child if child && child.host == origin.host
  end
end

Master::Trace::Dmesg.attach("links0", "master0", "#{seen.length} pages, #{findings.length} findings")
findings.each { |finding| Master::Trace::Dmesg.status("links0", finding.inspect, io: $stderr) }
Master::Trace::Dmesg.status("links0", "clean") if findings.empty?
exit 1 unless findings.empty?
