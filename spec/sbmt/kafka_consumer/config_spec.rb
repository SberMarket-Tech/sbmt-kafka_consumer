# frozen_string_literal: true

require "rails_helper"

describe Sbmt::KafkaConsumer::Config, type: :config do
  context "when app initialized" do
    let(:default_env) {
      {
        "KAFKA_CONSUMER_AUTH__KIND" => "sasl_plaintext",
        "KAFKA_CONSUMER_AUTH__SASL_USERNAME" => "username",
        "KAFKA_CONSUMER_AUTH__SASL_PASSWORD" => "password",
        "KAFKA_CONSUMER_AUTH__SASL_MECHANISM" => "PLAIN",

        "KAFKA_CONSUMER_KAFKA__SERVERS" => "server1:9092,server2:9092",

        "KAFKA_CONSUMER_CLIENT_ID" => "client-id"
      }
    }
    let(:config) { described_class.new }

    it "properly merges rdkafka options" do
      with_env(default_env) do
        expect(config.to_rdkafka_options)
          .to eq(
            "bootstrap.servers": "server1:9092,server2:9092",
            "security.protocol": "sasl_plaintext",
            "sasl.mechanism": "PLAIN",
            "sasl.password": "password",
            "sasl.username": "username",
            # loaded from kafka_consumer.yml
            "allow.auto.create.topics": true
          )
      end
    end
  end
end
