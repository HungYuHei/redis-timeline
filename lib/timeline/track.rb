module Timeline::Track
  extend ActiveSupport::Concern

  GLOBAL_ITEM = :global_item

  module ClassMethods
    def track(name, options={})
      callback = options.delete(:on) || :create
      method_name = "track_#{name}_after_#{callback}".to_sym
      define_activity_method method_name, actor: options.delete(:actor),
                                          object: options.delete(:object),
                                          target: options.delete(:target),
                                          actor_followers_ids: options.delete(:actor_followers_ids),
                                          category_follower_ids: options.delete(:category_follower_ids),
                                          post_tags_follower_ids: options.delete(:post_tags_follower_ids),
                                          music_type_genre_follower_ids: options.delete(:music_type_genre_follower_ids),
                                          verb: name,
                                          merge_similar: options[:merge_similar],
                                          mentionable: options.delete(:mentionable)

      send "after_#{callback}".to_sym, method_name, if: options.delete(:if)
    end

    private
      def define_activity_method(method_name, options={})
        define_method method_name do
          @actor = send(options[:actor])
          @fields_for = {}
          @object = set_object(options[:object])
          @target = !options[:target].nil? ? send(options[:target].to_sym) : nil
          @extra_fields ||= nil
          @merge_similar = options[:merge_similar] == true ? true : false
          @actor_followers_ids = send(options[:actor_followers_ids].to_sym)
          @category_follower_ids = send(options[:category_follower_ids].to_sym)
          @post_tags_follower_ids = send(options[:post_tags_follower_ids].to_sym)
          @music_type_genre_follower_ids = send(options[:music_type_genre_follower_ids].to_sym)
          @mentionable = options[:mentionable]
          add_activity(activity(verb: options[:verb]))
        end
      end
  end

  protected
    def activity(options={})
      {
        cache_key: "#{options[:verb]}_u#{@actor.id}_o#{@object.id}_#{Time.now.to_i}",
        #verb: options[:verb],
        actor: object_content(@actor),
        #object: object_content(@object),
        target: object_content(@target),
        action: action,
        created_at: created_at
      }
    end

    def add_activity(activity_item)
      redis_store_item(activity_item)
      add_activity_by_global(activity_item)
      add_activity_by_user(activity_item[:actor][:id], activity_item)
      add_mentions(activity_item)
      add_activity_to_follower_ids(activity_item)
    end

    def add_activity_by_global(activity_item)
      redis_add "global:activity", activity_item
    end

    def add_activity_by_user(user_id, activity_item)
      redis_add "user:id:#{user_id}:posts", activity_item
    end

    def add_activity_to_follower_ids(activity_item)
      @uniq_ids = @actor_followers_ids.clone

      @uniq_ids.concat(@category_follower_ids)
               .concat(@post_tags_follower_ids)
               .concat(music_type_genre_follower_ids)

      @uniq_ids.uniq.each { |id| add_activity_to_user(id, activity_item) }

      # order is matter since the first one will be overwritten
      @music_type_genre_follower_ids.each { |id| add_activity_reasonto_user(id, activity_item, :following_music_type_genre) }
      @category_follower_ids.each { |id| add_activity_reasonto_user(id, activity_item, :following_post_category) }
      @post_tags_follower_ids.each { |id| add_activity_reasonto_user(id, activity_item, :following_post_tag) }
      @actor_followers_ids.each { |id| add_activity_reasonto_user(id, activity_item, :following_user) }
    end

    def add_activity_to_user(user_id, activity_item)
      Timeline.redis.zadd "user:id:#{user_id}:activity", activity_item[:created_at].to_i, activity_item[:cache_key]
    end

    def add_activity_reasonto_user(user_id, activity_item, reason)
      Timeline.redis.hset "user:id:#{user_id}:reason", activity_item[:cache_key], reason
    end

    def add_mentions(activity_item)
      return unless @mentionable and @object.send(@mentionable)
      @object.send(@mentionable).scan(/@\w+/).each do |mention|
        if user = @actor.class.find_by_username(mention[1..-1])
          add_mention_to_user(user.id, activity_item)
        end
      end
    end

    def add_mention_to_user(user_id, activity_item)
      redis_add "user:id:#{user_id}:mentions", activity_item
    end

    def extra_fields_for(object)
      return {} unless @fields_for.has_key?(object.class.to_s.downcase.to_sym)
      @fields_for[object.class.to_s.downcase.to_sym].inject({}) do |sum, method|
        sum[method.to_sym] = @object.send(method.to_sym)
        sum
      end
    end

    def redis_add(list, activity_item)
      Timeline.redis.lpush list, activity_item[:cache_key]
    end

    def redis_store_item(activity_item)
      if @merge_similar
        # Merge similar item with last
        last_item_text = Timeline.get_list(:list_name => "user:id:#{activity_item[:actor][:id]}:posts", :start => 0, :end => 1).first
        if last_item_text
          last_item = Timeline::Activity.new Timeline.decode(last_item_text)
          if last_item[:verb].to_s == activity_item[:verb].to_s and last_item[:target] == activity_item[:target]
            activity_item[:object] = [last_item[:object], activity_item[:object]].flatten.uniq
          end
          # Remove last similar item, it will merge to new item
          Timeline.redis.hdel GLOBAL_ITEM, last_item[:cache_key]
        end
      end
      Timeline.redis.hset GLOBAL_ITEM, activity_item[:cache_key], Timeline.encode(activity_item)
    end

    def set_object(object)
      case
      when object.is_a?(Symbol)
        send(object)
      when object.is_a?(Array)
        @fields_for[self.class.to_s.downcase.to_sym] = object
        self
      else
        self
      end
    end

    def object_content(obj)
      case
      when obj.is_a?(Post)
        {
          type: obj.class.to_s.downcase!,
          id: obj.id.to_s,
          title: obj.title,
          content: obj.truncated_content,
          tags: obj.tags,
          comments_count: obj.comments_count,
          like_count: obj.liker_ids.size,
          created_at: obj.created_at,
          first_original_image_url: obj.first_original_image_url,
          user: { name: obj.user.name, uid: obj.user.uid }
        }
      when obj.is_a?(Music)
        {
          type: obj.class.to_s.downcase!,
          id: obj.id.to_s,
          title: obj.name,
          content: obj.description,
          cover_url: obj.cover.url
        }
      when obj.is_a?(User)
        {
          type: obj.class.to_s.downcase!,
          id: obj.id.to_s,
          name: obj.name,
          uid: obj.uid,
          avatar_url: obj.avatar.url,
          weibo_name: obj.weibo_name,
          douban_name: obj.douban_name
        }
      else
        nil
      end
    end

end
