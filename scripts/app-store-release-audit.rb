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
read = lambda do |path, payload = nil|
    uri = URI("https://api.appstoreconnect.apple.com/v1/#{path}")
    request = payload ? Net::HTTP::Patch.new(uri) : Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    if payload
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
    end
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(request) }
    body = JSON.parse(response.body)
    abort JSON.generate({ path: path, status: response.code, errors: body["errors"] }) unless response.is_a?(Net::HTTPSuccess)
    body.fetch("data")
end

versions = read.call("apps/6804230516/appStoreVersions?filter[platform]=IOS&limit=20")
puts JSON.generate({ versions: versions.map { |version| { id: version["id"], attributes: version["attributes"].slice("versionString", "appStoreState", "appVersionState", "releaseType", "copyright") } } })
version = versions.find { |item| item.dig("attributes", "versionString") == "1.1.1" }
abort "Missing 1.1.1 draft" unless version
if ARGV == ["prepare"]
    abort "The draft is no longer editable" unless version.dig("attributes", "appStoreState") == "PREPARE_FOR_SUBMISSION"
    require "fastlane"
    require "deliver"
    require "spaceship"
    Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
        key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
        issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
        key: raw.include?("BEGIN PRIVATE KEY") ? raw.gsub('\\n', "\n") : Base64.decode64(raw),
        duration: 1200
    )
    options = FastlaneCore::Configuration.create(Deliver::Options.available_options, {
        app_identifier: "com.fitfight.mvp", app_version: "1.1.1",
        skip_binary_upload: true, skip_app_version_update: true,
        skip_metadata: true, skip_screenshots: false,
        screenshots_path: File.expand_path("../docs/app-store/2026-09-15", __dir__),
        overwrite_screenshots: true, submit_for_review: false,
        automatic_release: false, run_precheck_before_submit: false, force: true
    })
    Deliver::Runner.new(options).run

    detail = read.call("appStoreVersions/#{version.fetch('id')}/appStoreReviewDetail")
    notes = detail.dig("attributes", "notes").gsub(/When configured, OpenRouter.*?as well\./m,
        "AI-generated daily-status notifications and recaps are disabled in production. Other optional notification types remain available. The Privacy Policy describes crash reporting and feedback processors.")
        .sub("reactions, and daily status.", "and reactions.")
    read.call("appStoreReviewDetails/#{detail.fetch('id')}", { data: { type: "appStoreReviewDetails", id: detail.fetch("id"), attributes: { notes: notes } } })

    info = read.call("apps/6804230516/appInfos").find { |item| item.dig("attributes", "state") == "PREPARE_FOR_SUBMISSION" }
    abort "Missing editable app information" unless info
    age = read.call("appInfos/#{info.fetch('id')}/ageRatingDeclaration")
    read.call("ageRatingDeclarations/#{age.fetch('id')}", {
        data: { type: "ageRatingDeclarations", id: age.fetch("id"), attributes: {
            healthOrWellnessTopics: true, messagingAndChat: true, socialMedia: true
        } }
    })
end
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
