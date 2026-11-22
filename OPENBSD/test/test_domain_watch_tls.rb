# frozen_string_literal: true

require "minitest/autorun"
require "openssl"
require_relative "../bin/domain_watch"

# The offline half of `domain_watch.rb --tls`: which hosts it probes and how it
# decides a certificate covers one. The network half is run by hand on the day.
class TestDomainWatchTls < Minitest::Test
  def certificate(*names)
    key = OpenSSL::PKey::EC.generate("prime256v1")
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=#{names.first}")
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 86_400
    ext = OpenSSL::X509::ExtensionFactory.new(cert, cert)
    cert.add_extension(ext.create_extension("subjectAltName", names.map { |n| "DNS:#{n}" }.join(",")))
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  def relayd_keypairs
    File.readlines(Deploy::DomainWatch::RELAYD_CONF, encoding: "UTF-8").filter_map do |line|
      line.sub(/#.*/, "").match(/tls keypair "([^"]+)"/)&.captures&.first
    end.uniq
  end

  def active_certificate_hosts
    File.read(Deploy::DomainWatch::ACME_CONF, encoding: "UTF-8").scan(
      /domain "([^"]+)" \{\s*alternative names \{([^}]*)\}/
    ).flat_map do |apex, names|
      next [] unless relayd_keypairs.include?(apex)

      [apex, *names.scan(/"([^"]+)"/).flatten.reject { |host| host.start_with?("mail.") }]
    end
  end

  def test_every_relayd_keypair_is_probed
    hosts = Deploy::DomainWatch.tls_hosts

    relayd_keypairs.each { |name| assert_includes hosts, name }
    assert_equal hosts.uniq, hosts
  end

  def test_every_san_for_an_active_relayd_certificate_is_probed
    expected = active_certificate_hosts
    hosts = Deploy::DomainWatch.tls_hosts

    assert_operator expected.size, :>, 10
    expected.each { |name| assert_includes hosts, name }
  end

  def test_standalone_application_www_hosts_are_probed
    hosts = Deploy::DomainWatch.tls_hosts

    assert_includes hosts, "www.amberapp.art"
    assert_includes hosts, "www.bsdports.org"
  end

  def test_mail_san_is_not_treated_as_a_website
    refute_includes Deploy::DomainWatch.tls_hosts, "mail.brgen.no"
  end

  def test_unserved_city_certificates_are_not_added_to_the_tls_probe
    hosts = Deploy::DomainWatch.tls_hosts
    pending = RenderDns.city_zones.find { |domain, subdomains| subdomains.any? && !relayd_keypairs.include?(domain) }

    refute_nil pending, "fixture needs at least one city zone without a relayd keypair"
    refute_includes hosts, "www.#{pending.first}"
    refute_includes hosts, "marketplace.#{pending.first}"
  end

  def test_a_certificate_covers_its_names_and_one_wildcard_label_only
    cert = certificate("brgen.no", "tv.brgen.no", "*.example.org")

    assert Deploy::DomainWatch.covers?(cert, "tv.brgen.no")
    assert Deploy::DomainWatch.covers?(cert, "www.example.org")
    refute Deploy::DomainWatch.covers?(cert, "dating.brgen.no"), "a name absent from the SANs must not pass"
    refute Deploy::DomainWatch.covers?(cert, "a.b.example.org"), "a wildcard spans one label"
  end
end
