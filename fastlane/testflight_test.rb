# frozen_string_literal: true

gem "minitest", "~> 5.0"
require "minitest/autorun"
require "minitest/mock"
require "ostruct"

# Exercise the real lane without signing, uploading, or contacting Apple.
$LOADED_FEATURES << "spaceship.rb"
module Spaceship
  module ConnectAPI
    class App
      def self.find(_identifier); end
    end

    class Build
      def self.all(**_options); end
    end

  end
end

class ReleaseAvailabilityTest < Minitest::Test
  AppleApp = Struct.new(:groups, :live, :candidate) do
    def id = "1234"
    def get_beta_groups = groups
    def get_app_store_versions(filter:, includes:)
      raise "Only installable App Store builds may become mandatory" unless filter == {
        platform: "IOS", appVersionState: "READY_FOR_DISTRIBUTION"
      } && includes == "build"
      live ? [live] : []
    end
    def get_latest_app_store_version(**) = candidate
  end

  def setup
    @lane = TestFlightLane.new
    @older = OpenStruct.new(
      id: "old", version: "153", app_version: "1.0.0", processing_state: "VALID", expired: false,
      build_beta_detail: OpenStruct.new(external_build_state: "IN_BETA_TESTING")
    )
    @newer = OpenStruct.new(
      id: "new", version: "160", app_version: "1.0.0", processing_state: "VALID", expired: false,
      build_beta_detail: OpenStruct.new(external_build_state: "WAITING_FOR_BETA_REVIEW")
    )
    @group = OpenStruct.new(is_internal_group: false, fetch_builds: [@older, @newer])
    @app = AppleApp.new([@group], nil, nil)
    @registered = [{ "channel" => "staging", "version" => "1.0.0", "build" => 160 }]
    @previous = {}
  end

  def manifest
    Spaceship::ConnectAPI::Build.stub(:all, [@older, @newer]) do
      @lane.available_app_releases(@app, @registered, @previous)
    end
  end

  def test_pending_review_does_not_replace_the_available_build_or_enable_enforcement
    policy = manifest.fetch("staging")
    assert_equal 153, policy.fetch("latest").fetch("build")
    assert_equal false, policy.fetch("enforced")
    assert_equal 160, policy.fetch("review").fetch("build")
    assert_equal 160, policy.fetch("internal").fetch("build")
  end

  def test_approval_and_group_availability_automatically_require_the_new_build
    @newer.build_beta_detail.external_build_state = "IN_BETA_TESTING"
    policy = manifest.fetch("staging")
    assert_equal 160, policy.fetch("latest").fetch("build")
    assert_nil policy.fetch("review")
    assert_nil policy.fetch("internal")
    assert_equal true, policy.fetch("enforced")
  end

  def test_a_build_missing_from_an_external_group_is_not_yet_mandatory
    @newer.build_beta_detail.external_build_state = "IN_BETA_TESTING"
    @app.groups << OpenStruct.new(is_internal_group: false, fetch_builds: [@older])
    policy = manifest.fetch("staging")
    assert_equal 153, policy.fetch("latest").fetch("build")
    assert_equal 160, policy.fetch("internal").fetch("build")
    assert_equal 160, policy.fetch("review").fetch("build")
  end

  def test_beta_review_is_admitted_but_unsubmitted_and_unregistered_builds_are_not
    @newer.build_beta_detail.external_build_state = "IN_BETA_REVIEW"
    assert_equal 160, manifest.dig("staging", "review", "build")
    @newer.build_beta_detail.external_build_state = "READY_FOR_BETA_SUBMISSION"
    policy = manifest.fetch("staging")
    assert_equal 153, policy.fetch("latest").fetch("build")
    assert_equal 160, policy.fetch("review").fetch("build")
    assert_equal 160, policy.fetch("internal").fetch("build")
    @newer.build_beta_detail.external_build_state = "IN_BETA_REVIEW"
    @registered.clear
    assert_nil manifest.dig("staging", "review")
    assert_nil manifest.dig("staging", "internal")
  end

  def test_internal_groups_do_not_hold_back_an_external_release
    @newer.build_beta_detail.external_build_state = "IN_BETA_TESTING"
    @app.groups << OpenStruct.new(is_internal_group: true, fetch_builds: [])
    assert_equal 160, manifest.dig("staging", "latest", "build")
    assert_nil manifest.dig("staging", "internal")
  end

  def test_internal_only_latest_is_offered_without_making_friends_update
    @newer.build_beta_detail.external_build_state = "READY_FOR_BETA_SUBMISSION"
    mid = OpenStruct.new(
      id: "mid", version: "155", app_version: "1.0.0", processing_state: "VALID", expired: false,
      build_beta_detail: OpenStruct.new(external_build_state: "READY_FOR_BETA_SUBMISSION")
    )
    @registered = [
      { "channel" => "staging", "version" => "1.0.0", "build" => 153 },
      { "channel" => "staging", "version" => "1.0.0", "build" => 155 },
      { "channel" => "staging", "version" => "1.0.0", "build" => 160 }
    ]
    @previous = { "staging" => { "enforced" => true } }
    Spaceship::ConnectAPI::Build.stub(:all, [@older, mid, @newer]) do
      policy = @lane.available_app_releases(@app, @registered, @previous).fetch("staging")
      assert_equal 153, policy.fetch("latest").fetch("build")
      assert_equal 160, policy.fetch("internal").fetch("build")
      assert_equal 160, policy.fetch("review").fetch("build")
      assert_equal true, policy.fetch("enforced")
    end
  end

  def test_expired_or_unprocessed_builds_do_not_become_mandatory
    @newer.build_beta_detail.external_build_state = "IN_BETA_TESTING"
    @newer.expired = true
    assert_equal 153, manifest.dig("staging", "latest", "build")
    @newer.expired = false
    @newer.processing_state = "PROCESSING"
    assert_equal 153, manifest.dig("staging", "latest", "build")
  end

  def test_production_review_does_not_replace_the_public_release
    @app.live = OpenStruct.new(version_string: "1.0.0", build: OpenStruct.new(version: "140"))
    @app.candidate = OpenStruct.new(version_string: "1.1.0", build: OpenStruct.new(version: "170"))
    @registered << { "channel" => "prod", "version" => "1.1.0", "build" => 170 }
    policy = manifest.fetch("prod")
    assert_equal 140, policy.fetch("latest").fetch("build")
    assert_equal 170, policy.fetch("review").fetch("build")
    assert_nil policy.fetch("internal")
    assert_equal false, policy.fetch("enforced")
    @app.live = @app.candidate
    policy = manifest.fetch("prod")
    assert_equal 170, policy.fetch("latest").fetch("build")
    assert_nil policy.fetch("review")
    assert_equal true, policy.fetch("enforced")
  end

  def test_two_part_app_store_version_is_written_as_marketing_version
    @app.live = OpenStruct.new(version_string: "1.0", build: OpenStruct.new(version: "113"))
    policy = manifest.fetch("prod")
    assert_equal "1.0.0", policy.fetch("latest").fetch("version")
    assert_equal 113, policy.fetch("latest").fetch("build")
    assert_equal false, policy.fetch("enforced")
  end

  def test_first_app_store_review_can_run_before_a_public_release_exists
    @app.candidate = OpenStruct.new(version_string: "1.0.0", build: OpenStruct.new(version: "170"))
    @registered << { "channel" => "prod", "version" => "1.0.0", "build" => 170 }
    assert_nil manifest.dig("prod", "latest")
    assert_equal 170, manifest.dig("prod", "review", "build")
    assert_nil manifest.dig("prod", "internal")
  end

  def test_enforcement_cannot_be_disabled_by_a_release_built_without_the_gate
    @previous = { "staging" => { "enforced" => true } }
    assert_raises(RuntimeError) { manifest }
  end
end

module UI
  def self.message(_text); end
  def self.success(_text); end
  def self.important(_text); end
  def self.user_error!(text) = raise(text)
end

module Actions
  def self.lane_context = { ipa: "test.ipa" }
end

module SharedValues
  IPA_OUTPUT_PATH = :ipa
end

class TestFlightLane
  attr_reader :uploads, :pointers
  attr_accessor :distribution_error

  def initialize
    @lanes = {}
    @uploads = []
    @pointers = []
    instance_eval(File.read(File.join(__dir__, "Fastfile")), "Fastfile")
  end

  def default_platform(_name); end
  def platform(_name) = yield
  def desc(_text); end
  def lane(name, &block) = @lanes[name] = block
  def is_ci = false
  def app_store_connect_api_key(**_options) = { key_id: "test-key" }
  def latest_testflight_build_number(**_options) = 153
  def get_version_number(**_options) = "1.0.0"
  def build_app(**_options); end

  def upload_to_testflight(**options)
    @uploads << options
    raise distribution_error if distribution_error && options[:distribute_external]
  end

  def run_beta
    stub(:write_api_key_file, nil) do
      stub(:revoke_stale_certificates, nil) do
        stub(:verify_healthkit_background_delivery, nil) do
          stub(:record_uploaded_release, ->(*args) { @pointers << args }) do
            ENV.stub(:fetch, "test") { @lanes.fetch(:beta).call }
          end
        end
      end
    end
  end
end

class TestFlightTest < Minitest::Test
  def setup
    @lane = TestFlightLane.new
    @groups = [
      OpenStruct.new(id: "internal", name: "Tester", is_internal_group: true),
      OpenStruct.new(id: "external", name: "External Testers", is_internal_group: false),
      OpenStruct.new(id: "friends", name: "Friends Beta", is_internal_group: false)
    ]
    @app = OpenStruct.new(id: "app", get_beta_groups: @groups)
    @build = OpenStruct.new(
      processing_state: "VALID", expired: false,
      build_beta_detail: OpenStruct.new(external_build_state: "WAITING_FOR_BETA_REVIEW")
    )
  end

  def with_apple
    Spaceship::ConnectAPI::App.stub(:find, @app) do
      Spaceship::ConnectAPI::Build.stub(:all, [@build]) { yield }
    end
  end

  def test_upload_waits_for_processing_then_assigns_every_external_group
    with_apple { @lane.run_beta }
    assert_equal 2, @lane.uploads.length
    upload = @lane.uploads.first
    assert_equal false, upload[:skip_waiting_for_build_processing]
    assert_equal true, upload[:skip_submission]
    assert_equal false, upload[:distribute_external]
    assert_equal false, upload[:notify_external_testers]
    refute upload.key?(:groups)
    refute_equal true, upload[:distribute_only]
    refute_equal true, upload[:submit_beta_review]
    everyone = @lane.uploads.last
    assert_equal true, everyone[:distribute_only]
    assert_equal true, everyone[:distribute_external]
    assert_equal ["external", "friends"], everyone[:groups]
    assert_equal true, everyone[:submit_beta_review]
    assert_equal true, everyone[:notify_external_testers]
    assert_equal false, everyone[:skip_submission]
    assert_equal [["staging", "1.0.0", 154]], @lane.pointers
  end

  def test_external_submission_failure_fails_the_lane
    @lane.distribution_error = "Apple rejected the beta submission"
    error = assert_raises(RuntimeError) { with_apple { @lane.run_beta } }
    assert_equal "Apple rejected the beta submission", error.message
    assert_equal 2, @lane.uploads.length
    assert_equal true, @lane.uploads.last[:distribute_external]
    assert_equal [["staging", "1.0.0", 154]], @lane.pointers
  end

  def test_missing_friends_group_fails_after_internal_upload
    @groups.reject! { |group| group.name == "Friends Beta" }
    error = assert_raises(RuntimeError) { with_apple { @lane.run_beta } }
    assert_match(/Friends Beta/, error.message)
    assert_equal 1, @lane.uploads.length
    assert_equal false, @lane.uploads.first[:distribute_external]
    assert_equal [["staging", "1.0.0", 154]], @lane.pointers
  end

  def test_missing_internal_group_fails_after_internal_upload
    @groups.reject!(&:is_internal_group)
    error = assert_raises(RuntimeError) { with_apple { @lane.run_beta } }
    assert_match(/No Internal TestFlight group/, error.message)
    assert_equal 1, @lane.uploads.length
    assert_equal [["staging", "1.0.0", 154]], @lane.pointers
  end

  def test_missing_all_external_groups_fails_after_internal_upload
    @groups.reject! { |group| !group.is_internal_group }
    error = assert_raises(RuntimeError) { with_apple { @lane.run_beta } }
    assert_match(/No External TestFlight groups/, error.message)
    assert_equal 1, @lane.uploads.length
    assert_equal [["staging", "1.0.0", 154]], @lane.pointers
  end

  def test_release_version_mismatch_fails_before_upload
    ENV["FITFIGHT_RELEASE_VERSION"] = "1.0.1"
    error = assert_raises(RuntimeError) { with_apple { @lane.run_beta } }
    assert_match(/does not match release version 1.0.1/, error.message)
    assert_empty @lane.uploads
  ensure
    ENV.delete("FITFIGHT_RELEASE_VERSION")
  end
end
