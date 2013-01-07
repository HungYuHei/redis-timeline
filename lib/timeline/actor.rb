module Timeline::Actor
  extend ActiveSupport::Concern

  included do
    def timeline(options={})
      Timeline.get_list(timeline_options(options)).map do |item|
        Timeline::Activity.new(Timeline.decode(item[0]).merge!({ reason: item[1] }))
      end
    end

    private
      def timeline_options(options)
        defaults = { list_name: "user:id:#{self.id}:activity", reason_field: "user:id:#{self.id}:reason", start: 0, end: 19 }
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
        end
      end
  end
end
