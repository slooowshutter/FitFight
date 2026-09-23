require "json"
require "jwt"
require "net/http"
require "openssl"

abort "Run this audit in GitHub Actions" unless ENV["GITHUB_ACTIONS"] == "true"
key = OpenSSL::PKey.read(ENV.fetch("APPLE_IAP_PRIVATE_KEY"))
now = Time.now.to_i
token = JWT.encode(
    { iss: ENV.fetch("APPLE_IAP_ISSUER_ID"), iat: now, exp: now + 300, aud: "appstoreconnect-v1", bid: "com.fitfight.mvp" },
    key, "ES256", { kid: ENV.fetch("APPLE_IAP_KEY_ID"), typ: "JWT" }
)

# Notification history is a read-only POST. Print no signed transactions or account data.
[
    ["Production", "https://api.storekit.apple.com"],
    ["Sandbox", "https://api.storekit-sandbox.apple.com"]
].each do |environment, origin|
    uri = URI("#{origin}/inApps/v1/notifications/history")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate({ startDate: (now - 3600) * 1000, endDate: now * 1000 })
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(request) }
    body = JSON.parse(response.body)
    abort JSON.generate({ environment: environment, status: response.code, error_code: body["errorCode"] }) unless response.is_a?(Net::HTTPSuccess)
    puts JSON.generate({ environment: environment, status: response.code, authorized: true, history_records: body.fetch("notificationHistory").length })
end
