# frozen_string_literal: true

FactoryBot.define do
  factory :messages_metadata, class: "SbmtKarafka::Messages::Metadata" do
    skip_create

    topic { "topic" }
    sequence(:offset) { |nr| nr }
    partition { 0 }
    deserializer { ->(message) { message.raw_payload } }
    timestamp { Time.now.utc }
  end
end
