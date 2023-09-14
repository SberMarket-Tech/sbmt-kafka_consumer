# frozen_string_literal: true

require_relative "tracer"

module Sbmt
  module KafkaConsumer
    module Instrumentation
      class OpenTelemetryTracer < ::Sbmt::KafkaConsumer::Instrumentation::Tracer
        class << self
          def enabled?
            !!@enabled
          end

          attr_writer :enabled
        end

        def enabled?
          self.class.enabled?
        end

        def trace(&block)
          return handle_consumed_one(&block) if @event_id == "consumer.consumed_one"
          return handle_inbox_consumed_one(&block) if @event_id == "consumer.inbox.consumed_one"
          return handle_error(&block) if @event_id == "error.occurred"

          yield
        end

        def handle_consumed_one
          return yield unless enabled?

          consumer = @payload[:caller]
          message = @payload[:message]

          parent_context = ::OpenTelemetry.propagation.extract(message.headers, getter: ::OpenTelemetry::Context::Propagation.text_map_getter)
          span_context = ::OpenTelemetry::Trace.current_span(parent_context).context
          links = [::OpenTelemetry::Trace::Link.new(span_context)] if span_context.valid?

          ::OpenTelemetry::Context.with_current(parent_context) do
            tracer.in_span("consume #{message.topic}", links: links, attributes: consumer_attrs(consumer, message), kind: :consumer) do
              yield
            end
          end
        end

        def handle_inbox_consumed_one
          return yield unless enabled?

          inbox_name = @payload[:inbox_name]
          event_name = @payload[:event_name]
          status = @payload[:status]

          inbox_attributes = {
            "inbox.inbox_name" => inbox_name,
            "inbox.event_name" => event_name,
            "inbox.status" => status
          }.compact

          tracer.in_span("inbox #{inbox_name} process", attributes: inbox_attributes, kind: :consumer) do
            yield
          end
        end

        def handle_error
          return yield unless enabled?

          current_span = OpenTelemetry::Trace.current_span
          current_span&.status = OpenTelemetry::Trace::Status.error

          yield
        end

        private

        def tracer
          ::Sbmt::KafkaConsumer::Instrumentation::OpenTelemetryLoader.instance.tracer
        end

        def consumer_attrs(consumer, message)
          attributes = {
            "messaging.system" => "kafka",
            "messaging.destination" => message.topic,
            "messaging.destination_kind" => "topic",
            "messaging.kafka.consumer_group" => consumer.topic.consumer_group.id,
            "messaging.kafka.partition" => message.partition,
            "messaging.kafka.offset" => message.offset
          }

          message_key = extract_message_key(message.key)
          attributes["messaging.kafka.message_key"] = message_key if message_key

          attributes.compact
        end

        def extract_message_key(key)
          # skip encode if already valid utf8
          return key if key.nil? || (key.encoding == Encoding::UTF_8 && key.valid_encoding?)

          key.encode(Encoding::UTF_8)
        rescue Encoding::UndefinedConversionError
          nil
        end
      end
    end
  end
end
