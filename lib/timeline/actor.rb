require 'time'

module Timeline::Actor
  extend ActiveSupport::Concern

  included do
    def timeline(options={})
      Timeline.get_list(timeline_options(options)).map do |item|
        Timeline::Activity.new(Timeline.decode(item[0]).merge!({ reason: item[1] }))
      end
    end

    def sync_timeline(user, count = 10)
      keys = Timeline.redis.lrange "user:id:#{user.id}:posts", 0, count
      return if keys.empty?
      items = Timeline.redis.hmget(Timeline::Track::GLOBAL_ITEM, *keys).map do |i|
        i = Timeline.decode(i)
        [Time.parse(i['created_at']).to_i, i['cache_key']]
      end
      Timeline.redis.zadd("user:id:#{id}:activity", items)

      reasons = items.reduce([]) { |arr, item| arr << item[1] << 'following_user' }
      Timeline.redis.hmset "user:id:#{id}:reason", *reasons
    end

    private
      def timeline_options(options)
        defaults = { list_name: "user:id:#{self.id}:activity", reason_field: "user:id:#{self.id}:reason", start: 0, end: 19, type: :activity }
        if options.is_a? Hash
          defaults.merge!(options)
        elsif options.is_a? Symbol
          case options
          when :global
            defaults.merge!(list_name: "global:activity")
          when :posts
            defaults.merge!(list_name: "user:id:#{self.id}:posts")
          when :mentions
            defaults.merge!(list_name: "user:id:#{self.id}:mentions")
          end
          defaults.merge!(type: options)
        end
      end
  end
end
