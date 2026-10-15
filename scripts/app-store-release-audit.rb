require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"

abort "Run this audit in GitHub Actions" unless ENV["GITHUB_ACTIONS"] == "true"
raw = ENV.fetch("APP_STORE_CONNECT_API_KEY")
key = OpenSSL::PKey.read(raw.include?("BEGIN PRIVATE KEY") ? raw.gsub('\\n', "\n") : Base64.decode64(raw))
token = JWT.encode(
    { iss: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"), iat: Time.now.to_i, exp: Time.now.to_i + 1200, aud: "appstoreconnect-v1" },
    key, "ES256", { kid: ENV.fetch("APP_STORE_CONNECT_KEY_ID"), typ: "JWT" }
)

# Keep contact information and credentials out of this public repository's CI log.
read = lambda do |path, payload = nil, method = Net::HTTP::Patch|
    uri = URI("https://api.appstoreconnect.apple.com#{path.start_with?('/') ? path : "/v1/#{path}"}")
    request = payload ? method.new(uri) : Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    if payload
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
    end
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(request) }
    body = JSON.parse(response.body.to_s.empty? ? "{}" : response.body)
    abort JSON.generate({ path: path, status: response.code, errors: body["errors"] }) unless response.is_a?(Net::HTTPSuccess)
    body["data"]
end

release_version = ENV.fetch("FITFIGHT_RELEASE_VERSION")
versions = read.call("apps/6804230516/appStoreVersions?filter[platform]=IOS&limit=20")
puts JSON.generate({ versions: versions.map { |version| { id: version["id"], attributes: version["attributes"].slice("versionString", "appStoreState", "appVersionState", "releaseType", "copyright") } } })
version = versions.find { |item| item.dig("attributes", "versionString") == release_version }
mode, production_build = ARGV
# Apple reviews a first In-App Purchase only in the same submission as an app version.
iap_versions = read.call("apps/6804230516/inAppPurchasesV2?limit=200").filter_map do |product|
    iap_versions_of_product = read.call("/v2/inAppPurchases/#{product.fetch('id')}/versions?limit=200")
    puts JSON.generate({ in_app_purchase: product["attributes"].slice("productId", "state", "inAppPurchaseType"), versions: iap_versions_of_product.map { |item| item["attributes"] } })
    iap_versions_of_product.find { |item| %w[PREPARE_FOR_SUBMISSION READY_FOR_REVIEW].include?(item.dig("attributes", "state")) }
end
read.call("apps/6804230516/reviewSubmissions?filter[platform]=IOS&limit=5").each do |submission|
    items = read.call("reviewSubmissions/#{submission.fetch('id')}/items?include=appStoreVersion,inAppPurchaseVersion")
    puts JSON.generate({ review_submission: submission["attributes"], items: items.map { |item| { state: item.dig("attributes", "state"), relationships: item["relationships"]&.transform_values { |value| value["data"] }&.compact } } })
end
builds = read.call("builds?filter[app]=6804230516&filter[preReleaseVersion.version]=#{release_version}&sort=-uploadedDate&limit=3")
puts JSON.generate({ builds: builds.map { |build| build["attributes"].slice("version", "processingState", "expired", "usesNonExemptEncryption") } })
if !version && mode == "draft"
    version = read.call("appStoreVersions", {
        data: {
            type: "appStoreVersions",
            attributes: { platform: "IOS", versionString: release_version, releaseType: "AFTER_APPROVAL", copyright: "2026 Marc Lamy" },
            relationships: { app: { data: { type: "apps", id: "6804230516" } } }
        }
    }, Net::HTTP::Post)
end
abort "Missing #{release_version} draft" unless version
selected_build = read.call("appStoreVersions/#{version.fetch('id')}/build")
puts JSON.generate({ selected_build: selected_build && selected_build.fetch("attributes").slice("version", "processingState", "usesNonExemptEncryption") })
if ["configure", "prepare", "draft", "submit"].include?(mode)
    abort "The draft is no longer editable" unless version.dig("attributes", "appStoreState") == "PREPARE_FOR_SUBMISSION"
    if ["draft", "submit"].include?(mode)
        abort "Expected an explicit production build number" unless production_build&.match?(/\A[1-9]\d*\z/)
        registry = JSON.parse(Net::HTTP.get(URI("https://raw.githubusercontent.com/slooowshutter/FitFight/testflight-latest/builds.json")))
        abort "This build is not registered as a production upload" unless registry.any? { |entry|
            entry["channel"] == "prod" && entry["version"] == release_version && entry["build"] == production_build.to_i
        }
        health = JSON.parse(Net::HTTP.get(URI("https://fitfight.app/api/health")))
        abort "Production is not ready" unless health["ok"] && health["backend"] == "prod" && health["schema"] == "ready" && health["profile_api"]
    end
    # Binary uploads skip metadata, so set the release option explicitly before review.
    configured = read.call("appStoreVersions/#{version.fetch('id')}", {
        data: { type: "appStoreVersions", id: version.fetch("id"), attributes: { releaseType: "AFTER_APPROVAL" } }
    })
    abort "Automatic public release is not enabled" unless configured.dig("attributes", "releaseType") == "AFTER_APPROVAL"
    puts JSON.generate({ configured_version: configured.fetch("attributes").slice("versionString", "appStoreState", "releaseType") })
    exit if mode == "configure"
    if ["draft", "submit"].include?(mode)
        build = builds.find { |item| item.dig("attributes", "version") == production_build }
        abort "Build #{production_build} is not a valid #{release_version} upload" unless build&.dig("attributes", "processingState") == "VALID" && build.dig("attributes", "usesNonExemptEncryption") == false
        read.call("appStoreVersions/#{version.fetch('id')}/relationships/build", { data: { type: "builds", id: build.fetch("id") } })
    end
    if mode == "draft"
        whats_new = {
            "en-US" => "Specials: collect limited animals, each with five step poses. Buy any Special once and keep it.\nCreate your own character: describe an animal, pick one of three portraits, and FitFight draws its five fitness poses.\nInvite a friend: when they connect Apple Health, you each get a free character.\nPast shows every finished round of a repeating fight, and trophies follow each round's winner.\nFull-body companions, faster Steps sync, and many fixes.",
            "fr-FR" => "Spéciaux : collectionnez des animaux en édition limitée, chacun avec cinq poses selon vos pas. Achetez un Spécial une fois et gardez-le.\nCréez votre personnage : décrivez un animal, choisissez l'un des trois portraits, et FitFight dessine ses cinq poses de sport.\nInvitez un ami : quand il connecte Santé d'Apple, vous recevez chacun un personnage gratuit.\nPassés affiche chaque manche terminée d'un défi récurrent, et les trophées suivent le gagnant de chaque manche.\nCompagnons en pied, synchronisation des pas plus rapide et de nombreuses corrections."
        }
        read.call("appStoreVersions/#{version.fetch('id')}/appStoreVersionLocalizations").each do |locale|
            read.call("appStoreVersionLocalizations/#{locale.fetch('id')}", {
                data: { type: "appStoreVersionLocalizations", id: locale.fetch("id"), attributes: { whatsNew: whats_new.fetch(locale.dig("attributes", "locale")) } }
            })
        end
        notes = File.read(File.expand_path("../docs/app-store/review-notes.md", __dir__))
            .split("## Paste into App Review Notes").last.split("\n## ").first
            .lines.grep(/\A>/).map { |line| line.sub(/\A> ?/, "") }.join.strip
        abort "App Review notes exceed 4,000 characters" if notes.length > 4000
        detail = read.call("appStoreVersions/#{version.fetch('id')}/appStoreReviewDetail")
        abort "Missing App Review contact details" unless detail
        read.call("appStoreReviewDetails/#{detail.fetch('id')}", { data: { type: "appStoreReviewDetails", id: detail.fetch("id"), attributes: { notes: notes } } })
    end
    if mode == "submit"
        abort "Expected both In-App Purchases ready for review" unless iap_versions.length == 2
        submission = read.call("apps/6804230516/reviewSubmissions?filter[platform]=IOS&filter[state]=READY_FOR_REVIEW").first ||
            read.call("reviewSubmissions", { data: { type: "reviewSubmissions", attributes: { platform: "IOS" }, relationships: { app: { data: { type: "apps", id: "6804230516" } } } } }, Net::HTTP::Post)
        # A rerun after a failed submit finds this submission with its items already added.
        [["appStoreVersion", "appStoreVersions", version.fetch("id")], *iap_versions.map { |item| ["inAppPurchaseVersion", "inAppPurchaseVersions", item.fetch("id")] }].each do |name, type, id|
            read.call("reviewSubmissionItems", {
                data: { type: "reviewSubmissionItems", relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: submission.fetch("id") } }, name => { data: { type: type, id: id } } } }
            }, Net::HTTP::Post)
        end if read.call("reviewSubmissions/#{submission.fetch('id')}/items").empty?
        read.call("reviewSubmissions/#{submission.fetch('id')}", { data: { type: "reviewSubmissions", id: submission.fetch("id"), attributes: { submitted: true } } })
        submitted = read.call("appStoreVersions/#{version.fetch('id')}")
        puts JSON.generate({ submitted_version: submitted.fetch("attributes").slice("versionString", "appStoreState", "appVersionState", "releaseType") })
        abort "Apple has not confirmed review submission" unless %w[WAITING_FOR_REVIEW IN_REVIEW].include?(submitted.dig("attributes", "appStoreState"))
        abort "Automatic public release is not enabled" unless submitted.dig("attributes", "releaseType") == "AFTER_APPROVAL"
        exit
    end
end
if mode == "prepare"
    require "fastlane"
    require "deliver"
    require "spaceship"
    Spaceship::ConnectAPI.token = Spaceship::ConnectAPI::Token.create(
        key_id: ENV.fetch("APP_STORE_CONNECT_KEY_ID"),
        issuer_id: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"),
        key: raw.include?("BEGIN PRIVATE KEY") ? raw.gsub('\\n', "\n") : Base64.decode64(raw),
        duration: 1200
    )
    # Deliver treats this environment name as a JSON hash; CI stores the raw key.
    ENV.delete("APP_STORE_CONNECT_API_KEY")
    values = {
        app_identifier: "com.fitfight.mvp", app_version: release_version,
        skip_binary_upload: true, skip_app_version_update: true,
        skip_metadata: true, skip_screenshots: false,
        screenshots_path: File.expand_path("../docs/app-store/2026-09-15", __dir__),
        overwrite_screenshots: true, submit_for_review: false,
        automatic_release: true, run_precheck_before_submit: false, force: true
    }
    options = FastlaneCore::Configuration.create(Deliver::Options.available_options, values)
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
