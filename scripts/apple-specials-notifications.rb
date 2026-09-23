require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"

abort "Run this setup only in preview release CI" unless ENV["GITHUB_ACTIONS"] == "true" && ENV["GITHUB_REF"] == "refs/heads/preview"
notification_url = "https://staging.fitfight.app/api/apple/specials/notifications/sandbox"
probe = Net::HTTP::Post.new(URI(notification_url))
probe["Content-Type"] = "application/json"
probe.body = JSON.generate({ signedPayload: "invalid-readiness-probe" })
response = Net::HTTP.start(probe.uri.hostname, probe.uri.port, use_ssl: true, read_timeout: 20) { |http| http.request(probe) }
abort "Deploy the staging Specials backend before TestFlight" unless response.code == "400" && JSON.parse(response.body)["code"] == "validation"

authorization = lambda do |key_id, issuer_id, raw_key, bundle_id = nil|
    pem = raw_key.include?("BEGIN PRIVATE KEY") ? raw_key.gsub('\\n', "\n") : Base64.decode64(raw_key)
    claims = { iss: issuer_id, iat: Time.now.to_i, exp: Time.now.to_i + 600, aud: "appstoreconnect-v1" }
    claims[:bid] = bundle_id if bundle_id
    JWT.encode(claims, OpenSSL::PKey.read(pem), "ES256", { kid: key_id, typ: "JWT" })
end
request_json = lambda do |method, url, token, payload = nil|
    uri = URI(url)
    request = method.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(payload) if payload
    result = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(request) }
    # Never print JWTs, purchase evidence or Apple account information in CI.
    abort "Apple notification setup HTTP #{result.code}" unless result.is_a?(Net::HTTPSuccess)
    JSON.parse(result.body)
end
asc_token = authorization.call(ENV.fetch("APP_STORE_CONNECT_KEY_ID"), ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"), ENV.fetch("APP_STORE_CONNECT_API_KEY"))
app_url = "https://api.appstoreconnect.apple.com/v1/apps/6804230516"
attributes = request_json.call(Net::HTTP::Get, app_url, asc_token).fetch("data").fetch("attributes")
existing = attributes["subscriptionStatusUrlForSandbox"]
abort "A different Sandbox notification endpoint is already configured" if existing && existing != notification_url
unless existing == notification_url && attributes["subscriptionStatusUrlVersionForSandbox"] == "V2"
    request_json.call(Net::HTTP::Patch, app_url, asc_token, {
        data: {
            type: "apps", id: "6804230516",
            attributes: { subscriptionStatusUrlForSandbox: notification_url, subscriptionStatusUrlVersionForSandbox: "V2" }
        }
    })
end
saved = request_json.call(Net::HTTP::Get, app_url, asc_token).fetch("data").fetch("attributes")
abort "Sandbox notification URL did not persist" unless saved["subscriptionStatusUrlForSandbox"] == notification_url && saved["subscriptionStatusUrlVersionForSandbox"] == "V2"

# Advisory from here: Apple's Sandbox delivery is flaky and must not block unrelated builds.
delivered = begin
    iap_token = authorization.call(ENV.fetch("APPLE_IAP_KEY_ID"), ENV.fetch("APPLE_IAP_ISSUER_ID"), ENV.fetch("APPLE_IAP_PRIVATE_KEY"), "com.fitfight.mvp")
    test_url = "https://api.storekit-sandbox.apple.com/inApps/v1/notifications/test"
    test_token = request_json.call(Net::HTTP::Post, test_url, iap_token).fetch("testNotificationToken")
    12.times.any? do
        sleep 5
        status = request_json.call(Net::HTTP::Get, "#{test_url}/#{test_token}", iap_token)
        status.fetch("sendAttempts", []).any? { |attempt| attempt["sendAttemptResult"] == "SUCCESS" }
    end
rescue SystemExit, StandardError
    false
end
if delivered
    puts JSON.generate({ environment: "Sandbox", notification_version: "V2", test_delivery: "SUCCESS", production_changed: false })
else
    puts "::warning::Apple has not confirmed Sandbox notification delivery; the upload continues"
end
