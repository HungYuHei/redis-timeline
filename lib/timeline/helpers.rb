require 'multi_json/version'

module Timeline
  module Helpers
    class DecodeException < StandardError; end

    def encode(object)
      if ::MultiJson::VERSION.to_f > 1.3
        ::MultiJson.dump(object)
      else
        ::MultiJson.encode(object)
      end
    end

    def decode(object)
      return unless object

      begin
        if ::MultiJson::VERSION.to_f > 1.3
          ::MultiJson.load(object)
        else
          ::MultiJson.decode(object)
        end
      rescue ::MultiJson::DecodeError => e
        raise DecodeException, e
      end
    end

    def get_list(options={})
      if options[:type] == :activity
        keys = Timeline.redis.zrevrange options[:list_name], options[:start], options[:end]
      else
        keys = Timeline.redis.lrange options[:list_name], options[:start], options[:end]
      end
      return [] if keys.blank?

      items = Timeline.redis.hmget(Timeline::Track::GLOBAL_ACTIVITY_ITEM, *keys)
      reasons = Timeline.redis.hmget(options[:reason_field], *keys)

      items.zip reasons
    end
  end
end
