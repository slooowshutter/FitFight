require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"

abort "Run this audit in GitHub Actions" unless ENV["GITHUB_ACTIONS"] == "true"
raw = ENV.fetch("APP_STORE_CONNECT_API_KEY")
key = OpenSSL::PKey.read(raw.include?("BEGIN PRIVATE KEY") ? raw.gsub('\\n', "\n") : Base64.decode64(raw))
token = JWT.encode(
    { iss: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"), iat: Time.now.to_i, exp: Time.now.to_i + 600, aud: "appstoreconnect-v1" },
    key, "ES256", { kid: ENV.fetch("APP_STORE_CONNECT_KEY_ID"), typ: "JWT" }
)

# Keep contact information and credentials out of this public repository's CI log.
read = lambda do |path|
    uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(request) }
    body = JSON.parse(response.body)
    abort JSON.generate({ path: path, status: response.code, errors: body["errors"] }) unless response.is_a?(Net::HTTPSuccess)
    body.fetch("data")
end

versions = read.call("apps/6804230516/appStoreVersions?filter[platform]=IOS&limit=20")
puts JSON.generate({ versions: versions.map { |version| { id: version["id"], attributes: version["attributes"].slice("versionString", "appStoreState", "appVersionState", "releaseType", "copyright") } } })
version = versions.find { |item| item.dig("attributes", "versionString") == "1.1.1" }
abort "Missing 1.1.1 draft" unless version
localizations = read.call("appStoreVersions/#{version.fetch('id')}/appStoreVersionLocalizations")
localizations.each do |locale|
    sets = read.call("appStoreVersionLocalizations/#{locale.fetch('id')}/appScreenshotSets")
    screenshots = sets.map do |set|
        files = read.call("appScreenshotSets/#{set.fetch('id')}/appScreenshots")
        { display: set.dig("attributes", "screenshotDisplayType"), files: files.map { |file| file["attributes"].slice("fileName", "assetDeliveryState") } }
    end
    puts JSON.generate({ locale: locale["attributes"], screenshots: screenshots })
end
review = read.call("appStoreVersions/#{version.fetch('id')}/appStoreReviewDetail").fetch("attributes")
puts JSON.generate({ review: review.slice("demoAccountRequired", "notes"), contact_complete: %w[contactFirstName contactLastName contactEmail contactPhone].all? { |name| !review[name].to_s.empty? } })
read.call("apps/6804230516/appInfos").each do |info|
    puts JSON.generate({ app_info: info["attributes"], age_rating: read.call("appInfos/#{info.fetch('id')}/ageRatingDeclaration")["attributes"] })
end
