# frozen_string_literal: true

module Sbmt
  module KafkaConsumer
    class InboxConsumer < BaseConsumer
      IDEMPOTENCY_HEADER_NAME = "Idempotency-Key"
      DEFAULT_SOURCE = "KAFKA"

      def self.consumer_klass(name:, inbox_item:, event_name: nil, skip_on_error: false)
        klass = Class.new(self)
        klass.const_set(:INBOX_ITEM_CLASS_NAME, inbox_item)
        klass.const_set(:EVENT_NAME, event_name)
        klass.const_set(:SKIP_ON_ERROR, skip_on_error)
        const_set("#{name.classify}Consumer", klass)
        klass
      end

      private

      def process_message(message)
        ::Sbmt::KafkaConsumer.monitor.instrument(
          "consumer.inbox.consumed_one", caller: self,
          message: message,
          message_uuid: message_uuid(message),
          inbox_name: inbox_name,
          event_name: event_name,
          status: "success"
        ) do
          process_inbox_item(message)
        end
      end

      def process_inbox_item(message)
        result = Sbmt::Outbox::CreateInboxItem.call(
          inbox_item_class,
          attributes: message_attrs(message)
        )

        if result.failure?
          raise "Failed consuming message for #{inbox_name}, message_uuid: #{message_uuid(message)}: #{result}"
        end

        item = result.success
        item.track_metrics_after_consume if item.respond_to?(:track_metrics_after_consume)
      rescue ActiveRecord::RecordNotUnique
        instrument_error("Skipped duplicate message for #{inbox_name}, message_uuid: #{message_uuid(message)}", message, "duplicate")
      rescue => ex
        instrument_error(ex, message)
        raise ex
      end

      def message_attrs(message)
        attrs = {
          proto_payload: message.raw_payload,
          options: {
            headers: message.metadata.headers,
            group_id: topic.consumer_group.id,
            topic: message.metadata.topic,
            partition: message.metadata.partition,
            source: DEFAULT_SOURCE
          }
        }

        if message_uuid(message)
          attrs[:uuid] = message_uuid(message)
        else
          # if message has no uuid (poisoned?), it will be generated later in Sbmt::Outbox::CreateInboxItem
          # so we just log it
          logger.error("message has no uuid, headers: #{message.metadata.headers}")
        end

        if message.metadata.key
          attrs[:event_key] = message.metadata.key
        else
          # if message has no partitioning key (poisoned?),
          # set it to something random like offset and log it
          attrs[:event_key] = message.offset
          logger.error("message has no partitioning key #{IDEMPOTENCY_HEADER_NAME}, headers: #{message.metadata.headers}")
        end

        attrs[:event_name] = event_name if inbox_item_class.has_attribute?(:event_name)

        attrs
      end

      def message_uuid(message)
        message.metadata.headers.fetch(IDEMPOTENCY_HEADER_NAME, nil)
      end

      def inbox_item_class
        @inbox_item_class ||= self.class::INBOX_ITEM_CLASS_NAME.constantize
      end

      def event_name
        @event_name ||= self.class::EVENT_NAME
      end

      def inbox_name
        inbox_item_class.box_name
      end

      def instrument_error(error, message, status = "failure")
        ::Sbmt::KafkaConsumer.monitor.instrument(
          "error.occurred",
          error: error,
          caller: self,
          message: message,
          inbox_name: inbox_name,
          event_name: event_name,
          status: status,
          type: "consumer.inbox.consume_one"
        )
      end
    end
  end
end
