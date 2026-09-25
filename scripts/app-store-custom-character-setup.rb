require "base64"
require "bigdecimal"
require "date"
require "json"
require "jwt"
require "net/http"
require "openssl"

abort "Run this setup in GitHub Actions" unless ENV["GITHUB_ACTIONS"] == "true"
mode = ARGV.fetch(0, "audit")
abort "Expected audit or prepare" unless ["audit", "prepare"].include?(mode)
product_id = "com.fitfight.mvp.custom_character"
app_id = "6804230516"
base_territory = "FRA"
customer_price = BigDecimal("4.99")

raw = ENV.fetch("APP_STORE_CONNECT_API_KEY")
key = OpenSSL::PKey.read(raw.include?("BEGIN PRIVATE KEY") ? raw.gsub('\\n', "\n") : Base64.decode64(raw))
token = JWT.encode(
    { iss: ENV.fetch("APP_STORE_CONNECT_ISSUER_ID"), iat: Time.now.to_i, exp: Time.now.to_i + 1200, aud: "appstoreconnect-v1" },
    key, "ES256", { kid: ENV.fetch("APP_STORE_CONNECT_KEY_ID"), typ: "JWT" }
)

request_apple = lambda do |path, payload = nil, allow_missing: false|
    uri = URI("https://api.appstoreconnect.apple.com#{path}")
    request = payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Accept"] = "application/json"
    if payload
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
    end
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 30) { |http| http.request(request) }
    return nil if allow_missing && response.code == "404"
    body = JSON.parse(response.body)
    unless response.is_a?(Net::HTTPSuccess)
        abort JSON.generate({ path: path, status: response.code, errors: body.fetch("errors", []).map { |error| error.slice("code", "title", "detail", "source") } })
    end
    body
end

products = []
path = "/v1/apps/#{app_id}/inAppPurchasesV2?limit=200"
while path
    page = request_apple.call(path)
    products.concat(page.fetch("data"))
    path = page.dig("links", "next")&.then { |link| URI(link).request_uri }
end
product = products.find { |item| item.fetch("attributes").fetch("productId") == product_id }
if !product && mode == "prepare"
    product = request_apple.call("/v2/inAppPurchases", {
        data: {
            type: "inAppPurchases",
            attributes: { name: "Custom character", productId: product_id, inAppPurchaseType: "CONSUMABLE" },
            relationships: { app: { data: { type: "apps", id: app_id } } }
        }
    }).fetch("data")
end
abort "Custom character product has not been prepared" unless product
attributes = product.fetch("attributes")
abort "Custom character must be consumable without Family Sharing" unless attributes.fetch("inAppPurchaseType") == "CONSUMABLE" && attributes.fetch("familySharable") == false
product_key = product.fetch("id")

versions = request_apple.call("/v2/inAppPurchases/#{product_key}/versions?limit=200").fetch("data")
version = versions.find { |item| item.fetch("attributes").fetch("state") == "PREPARE_FOR_SUBMISSION" }
if !version && versions.empty? && mode == "prepare"
    version = request_apple.call("/v1/inAppPurchaseVersions", {
        data: {
            type: "inAppPurchaseVersions",
            relationships: { inAppPurchase: { data: { type: "inAppPurchases", id: product_key } } }
        }
    }).fetch("data")
end
abort "Custom character metadata is unavailable for preparation" unless version || mode == "audit"
if version
    localizations = request_apple.call("/v1/inAppPurchaseVersions/#{version.fetch('id')}/localizations?limit=200").fetch("data")
    [
        ["en-US", "Custom character", "One character and five Steps images."],
        ["fr-FR", "Personnage personnalisé", "Un personnage et cinq images selon les pas."]
    ].each do |locale, name, description|
        abort "Apple purchase text is too long" unless name.length.between?(2, 30) && description.length <= 45
        existing = localizations.find { |item| item.fetch("attributes").fetch("locale") == locale }
        if existing
            abort "Existing character text differs" unless existing.fetch("attributes").slice("name", "description") == { "name" => name, "description" => description }
        elsif mode == "prepare"
            request_apple.call("/v2/inAppPurchaseLocalizations", {
                data: {
                    type: "inAppPurchaseLocalizations",
                    attributes: { locale: locale, name: name, description: description },
                    relationships: { version: { data: { type: "inAppPurchaseVersions", id: version.fetch("id") } } }
                }
            })
        else
            abort "Missing #{locale} character localization"
        end
    end
end

territories = request_apple.call("/v1/territories?limit=200").fetch("data").map { |item| item.fetch("id") }.sort
availability_path = "/v2/inAppPurchases/#{product_key}/inAppPurchaseAvailability"
availability = request_apple.call(availability_path, allow_missing: true)&.fetch("data")
if !availability && mode == "prepare"
    availability = request_apple.call("/v1/inAppPurchaseAvailabilities", {
        data: {
            type: "inAppPurchaseAvailabilities",
            attributes: { availableInNewTerritories: false },
            relationships: {
                inAppPurchase: { data: { type: "inAppPurchases", id: product_key } },
                availableTerritories: { data: territories.map { |id| { type: "territories", id: id } } }
            }
        }
    }).fetch("data")
end
abort "Custom character availability is missing" unless availability
saved_territories = request_apple.call("/v1/inAppPurchaseAvailabilities/#{availability.fetch('id')}/availableTerritories?limit=200").fetch("data").map { |item| item.fetch("id") }.sort
abort "Custom character territory configuration differs" unless saved_territories == territories

points = []
path = "/v2/inAppPurchases/#{product_key}/pricePoints?filter%5Bterritory%5D=#{base_territory}&include=territory&limit=8000"
while path
    page = request_apple.call(path)
    points.concat(page.fetch("data"))
    path = page.dig("links", "next")&.then { |link| URI(link).request_uri }
end
matching = points.select { |point|
    point.dig("relationships", "territory", "data", "id") == base_territory &&
        BigDecimal(point.fetch("attributes").fetch("customerPrice")) == customer_price
}
abort "Apple must provide exactly one EUR 4.99 price point" unless matching.length == 1
price_point_id = matching.first.fetch("id")
schedule_path = "/v2/inAppPurchases/#{product_key}/iapPriceSchedule?include=baseTerritory"
schedule = request_apple.call(schedule_path, allow_missing: true)&.fetch("data")
if !schedule && mode == "prepare"
    request_apple.call("/v1/inAppPurchasePriceSchedules", {
        data: {
            type: "inAppPurchasePriceSchedules",
            relationships: {
                inAppPurchase: { data: { type: "inAppPurchases", id: product_key } },
                baseTerritory: { data: { type: "territories", id: base_territory } },
                manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${character-price}" }] }
            }
        },
        included: [{
            type: "inAppPurchasePrices", id: "${character-price}",
            attributes: { startDate: nil, endDate: nil },
            relationships: {
                inAppPurchaseV2: { data: { type: "inAppPurchases", id: product_key } },
                inAppPurchasePricePoint: { data: { type: "inAppPurchasePricePoints", id: price_point_id } }
            }
        }]
    })
    schedule = request_apple.call(schedule_path).fetch("data")
end
abort "Custom character price schedule is missing" unless schedule
abort "Character base territory differs" unless schedule.dig("relationships", "baseTerritory", "data", "id") == base_territory
manual_prices = request_apple.call("/v1/inAppPurchasePriceSchedules/#{schedule.fetch('id')}/manualPrices?include=inAppPurchasePricePoint,territory&limit=200")
prices = manual_prices.fetch("data")
abort "Unexpected additional or scheduled character prices" unless prices.length == 1 && !manual_prices.dig("links", "next")
price = prices.first
price_attributes = price.fetch("attributes")
current_price = price_attributes["startDate"].nil? || Date.iso8601(price_attributes.fetch("startDate")) <= Date.today
abort "Character price did not verify as EUR 4.99 with no end date" unless price.dig("relationships", "inAppPurchasePricePoint", "data", "id") == price_point_id && current_price && price_attributes["endDate"].nil? && price_attributes.fetch("manual") == true

puts JSON.pretty_generate({
    app_id: app_id,
    product_id: product_id,
    type: attributes.fetch("inAppPurchaseType"),
    state: attributes.fetch("state"),
    family_sharing: attributes.fetch("familySharable"),
    base_territory: base_territory,
    currency: "EUR",
    customer_price: "4.99",
    available_territories: saved_territories.length,
    submitted_for_review: false
})
