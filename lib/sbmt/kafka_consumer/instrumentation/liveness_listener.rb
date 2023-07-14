# frozen_string_literal: true

module Sbmt
  module KafkaConsumer
    module Instrumentation
      class LivenessListener
        include ListenerHelper
        include KafkaConsumer::Probes::Probe

        def initialize(timeout_sec: 10)
          @consumer_groups = SbmtKarafka::App.routes.map(&:name)
          @timeout_sec = timeout_sec
          @polls = {}

          setup_subscription
        end

        def probe(_env)
          now = current_time
          timed_out_polls = select_timed_out_polls(now)
          return probe_ok groups: meta_from_polls(polls, now) if timed_out_polls.empty?

          probe_error failed_groups: meta_from_polls(timed_out_polls, now)
        end

        def on_connection_listener_fetch_loop(event)
          consumer_group = event.payload[:subscription_group].consumer_group
          polls[consumer_group.name] = current_time
        end

        private

        attr_reader :polls, :timeout_sec, :consumer_groups

        def current_time
          Time.now.utc
        end

        def select_timed_out_polls(now)
          raise "consumer_groups are empty. Please set them up" if consumer_groups.empty?

          consumer_groups.each_with_object({}) do |group, hash|
            last_poll_at = polls[group]
            next if last_poll_at && last_poll_at + timeout_sec >= now

            hash[group] = last_poll_at
          end
        end

        def meta_from_polls(polls, now)
          polls.each_with_object({}) do |(group, last_poll_at), hash|
            if last_poll_at.nil?
              hash[group] = {had_poll: false}
              next
            end

            hash[group] = {
              had_poll: true,
              last_poll_at: last_poll_at,
              seconds_since_last_poll: (now - last_poll_at).to_i
            }
          end
        end

        def setup_subscription
          SbmtKarafka::App.monitor.subscribe(self)
        end
      end
    end
  end
end