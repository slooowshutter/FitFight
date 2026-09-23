require "base64"
require "bigdecimal"
require "date"
require "json"
require "jwt"
require "net/http"
require "openssl"

abort "Run this setup in GitHub Actions" unless ENV["GITHUB_ACTIONS"] == "true"
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
        # Keep the signing key and authentication headers out of this public log.
        abort JSON.generate({ path: path, status: response.code, errors: body.fetch("errors").map { |error| error.slice("code", "title", "detail", "source") } })
    end
    body
end

catalog = JSON.parse(File.read(File.expand_path("../docs/design/source/companion/limited-editions.json", __dir__)))
abort "Expected 40 distinct Specials" unless catalog.length == 40 && catalog.map { |row| row.fetch("id") }.uniq.length == 40
mode = ARGV.fetch(0, "audit")
abort "Expected audit, prepare, price, or availability" unless ["audit", "prepare", "price", "availability"].include?(mode)
expected = catalog.map { |row| "com.fitfight.mvp.special.#{row.fetch('id').delete_prefix('limited-').tr('-', '_')}" }
products = []
path = "/v1/apps/6804230516/inAppPurchasesV2?limit=200"
while path
    page = request_apple.call(path)
    products.concat(page.fetch("data"))
    next_link = page.dig("links", "next")
    path = next_link && URI(next_link).request_uri
end

if mode == "prepare"
    catalog.zip(expected).each do |row, product_id|
        product = products.find { |item| item.fetch("attributes").fetch("productId") == product_id }
        unless product
            product = request_apple.call("/v2/inAppPurchases", {
                data: {
                    type: "inAppPurchases",
                    attributes: {
                        name: "Special: #{row.fetch('name')}",
                        productId: product_id,
                        inAppPurchaseType: "NON_CONSUMABLE"
                    },
                    relationships: { app: { data: { type: "apps", id: "6804230516" } } }
                }
            }).fetch("data")
            products << product
        end
        attributes = product.fetch("attributes")
        abort "A Special must be a non-consumable without Family Sharing" unless attributes.fetch("inAppPurchaseType") == "NON_CONSUMABLE" && attributes.fetch("familySharable") == false

        versions = request_apple.call("/v2/inAppPurchases/#{product.fetch('id')}/versions?limit=200").fetch("data")
        version = versions.find { |item| item.fetch("attributes").fetch("state") == "PREPARE_FOR_SUBMISSION" }
        abort "Special metadata is already in review or published" if !versions.empty? && !version
        unless version
            version = request_apple.call("/v1/inAppPurchaseVersions", {
                data: {
                    type: "inAppPurchaseVersions",
                    relationships: { inAppPurchase: { data: { type: "inAppPurchases", id: product.fetch("id") } } }
                }
            }).fetch("data")
        end
        localizations = request_apple.call("/v1/inAppPurchaseVersions/#{version.fetch('id')}/localizations?limit=200").fetch("data")
        french_name = row.fetch("id") == "limited-secretary-bird-stride" ? "Messager sagittaire, actif" : row.fetch("frenchName")
        [
            ["en-US", row.fetch("name"), "One-of-a-kind profile companion."],
            ["fr-FR", french_name, "Compagnon de profil en exemplaire unique."]
        ].each do |locale, name, description|
            abort "Apple purchase text is too long" unless name.length.between?(2, 30) && description.length <= 45
            existing = localizations.find { |item| item.fetch("attributes").fetch("locale") == locale }
            if existing
                abort "Existing Special text differs from this catalogue" unless existing.fetch("attributes").slice("name", "description") == { "name" => name, "description" => description }
                next
            end
            request_apple.call("/v2/inAppPurchaseLocalizations", {
                data: {
                    type: "inAppPurchaseLocalizations",
                    attributes: { locale: locale, name: name, description: description },
                    relationships: { version: { data: { type: "inAppPurchaseVersions", id: version.fetch("id") } } }
                }
            })
        end
    end
end

if mode == "availability"
    territories = request_apple.call("/v1/territories?limit=200").fetch("data").map { |item| item.fetch("id") }.sort
    expected.each do |product_id|
        product = products.find { |item| item.fetch("attributes").fetch("productId") == product_id }
        abort "Create every Special before availability" unless product
        product_key = product.fetch("id")
        versions = request_apple.call("/v2/inAppPurchases/#{product_key}/versions?limit=200").fetch("data")
        abort "Only unsold Special drafts can be configured" if versions.empty? || versions.any? { |version| version.fetch("attributes").fetch("state") != "PREPARE_FOR_SUBMISSION" }
        path = "/v2/inAppPurchases/#{product_key}/inAppPurchaseAvailability"
        availability = request_apple.call(path, allow_missing: true)&.fetch("data")
        unless availability
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
        saved = request_apple.call("/v1/inAppPurchaseAvailabilities/#{availability.fetch('id')}/availableTerritories?limit=200").fetch("data").map { |item| item.fetch("id") }.sort
        abort "Existing territory configuration differs" unless saved == territories
        puts JSON.generate({ product_id: product_id, available_territories: saved.length, submitted_for_review: false })
    end
end

verified_prices = []
if mode == "price"
    base_territory = "FRA"
    customer_price = BigDecimal("0.99")
    territory = request_apple.call("/v1/territories?limit=200").fetch("data").find { |item| item.fetch("id") == base_territory }
    abort "Apple did not return the base territory" unless territory
    abort "Expected a euro base territory" unless territory.fetch("attributes").fetch("currency") == "EUR"

    expected.each do |product_id|
        product = products.find { |item| item.fetch("attributes").fetch("productId") == product_id }
        abort "Create every Special before pricing" unless product
        attributes = product.fetch("attributes")
        abort "A Special must be a non-consumable without Family Sharing" unless attributes.fetch("inAppPurchaseType") == "NON_CONSUMABLE" && attributes.fetch("familySharable") == false
        product_key = product.fetch("id")
        versions = request_apple.call("/v2/inAppPurchases/#{product_key}/versions?limit=200").fetch("data")
        abort "Only unsold Special drafts can be priced by this setup" if versions.empty? || versions.any? { |version| version.fetch("attributes").fetch("state") != "PREPARE_FOR_SUBMISSION" }

        points = []
        path = "/v2/inAppPurchases/#{product_key}/pricePoints?filter%5Bterritory%5D=#{base_territory}&include=territory&limit=8000"
        while path
            page = request_apple.call(path)
            points.concat(page.fetch("data"))
            next_link = page.dig("links", "next")
            path = next_link && URI(next_link).request_uri
        end
        matches = points.select { |point|
            point.dig("relationships", "territory", "data", "id") == base_territory &&
                BigDecimal(point.fetch("attributes").fetch("customerPrice")) == customer_price
        }
        unless matches.length == 1
            abort JSON.generate({
                error: "Apple must provide exactly one EUR 0.99 price point",
                returned_points: points.length,
                matching_amount: points.select { |point| BigDecimal(point.fetch("attributes").fetch("customerPrice")) == customer_price }
            })
        end
        price_point_id = matches.first.fetch("id")

        schedule_path = "/v2/inAppPurchases/#{product_key}/iapPriceSchedule?include=baseTerritory"
        schedule = request_apple.call(schedule_path, allow_missing: true)&.fetch("data")
        unless schedule
            request_apple.call("/v1/inAppPurchasePriceSchedules", {
                data: {
                    type: "inAppPurchasePriceSchedules",
                    relationships: {
                        inAppPurchase: { data: { type: "inAppPurchases", id: product_key } },
                        baseTerritory: { data: { type: "territories", id: base_territory } },
                        manualPrices: { data: [{ type: "inAppPurchasePrices", id: "${special-price}" }] }
                    }
                },
                included: [{
                    type: "inAppPurchasePrices", id: "${special-price}",
                    attributes: { startDate: nil, endDate: nil },
                    relationships: {
                        inAppPurchaseV2: { data: { type: "inAppPurchases", id: product_key } },
                        inAppPurchasePricePoint: { data: { type: "inAppPurchasePricePoints", id: price_point_id } }
                    }
                }]
            })
            schedule = request_apple.call(schedule_path).fetch("data")
        end

        abort "Existing Special pricing has a different base territory" unless schedule.dig("relationships", "baseTerritory", "data", "id") == base_territory
        manual_prices = request_apple.call("/v1/inAppPurchasePriceSchedules/#{schedule.fetch('id')}/manualPrices?include=inAppPurchasePricePoint,territory&limit=200")
        prices = manual_prices.fetch("data")
        abort "Unexpected additional or scheduled Special prices" unless prices.length == 1 && !manual_prices.dig("links", "next")
        price = prices.first
        price_attributes = price.fetch("attributes")
        correct_price = price.dig("relationships", "inAppPurchasePricePoint", "data", "id") == price_point_id
        current_price = price_attributes["startDate"].nil? || Date.iso8601(price_attributes.fetch("startDate")) <= Date.today
        abort "Special price did not verify as EUR 0.99 with no end date" unless correct_price && current_price && price_attributes["endDate"].nil? && price_attributes.fetch("manual") == true
        verified_prices << { product_id: product_id, base_territory: base_territory, currency: "EUR", customer_price: "0.99" }
        puts "Verified #{product_id}: EUR 0.99"
    end
    abort "Not every Special price was verified" unless verified_prices.length == 40
end

puts JSON.pretty_generate({
    app_id: "6804230516",
    expected_specials: expected.length,
    existing_in_app_purchases: products.length,
    mode: mode,
    verified_prices: verified_prices,
    specials: products.filter_map { |product|
        attributes = product.fetch("attributes")
        next unless expected.include?(attributes.fetch("productId"))
        { id: product.fetch("id"), attributes: attributes.slice("productId", "name", "inAppPurchaseType", "state", "familySharable") }
    },
    missing: expected - products.map { |product| product.fetch("attributes").fetch("productId") }
})
