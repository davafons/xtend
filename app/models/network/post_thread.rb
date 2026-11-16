# One saved post with the conversation around it, built only from what Xtend collected: the posts it replies to
# (as far up as they were saved), the replies seen under it, and the posts seen quoting it. A short thread here
# means few replies were collected, not that few were written; X's reply count says how many there are.
class Network::PostThread
  MAX_ANCESTORS = 25

  attr_reader :post

  def initialize(x_id)
    @post = X::SourcePost.where(repost: false).find_by!(x_id: x_id.to_s)
    @owner = Current.workspace.owner_x_id.to_s
  end

  # The posts above, oldest first.
  def ancestors
    @ancestors ||= begin
      chain = []
      parent_id = post.parent_x_id
      while parent_id && chain.size < MAX_ANCESTORS && (parent = X::SourcePost.find_by(x_id: parent_id))
        chain.unshift(parent)
        parent_id = parent.parent_x_id
      end
      @missing_parent = parent_id.present?
      chain
    end
  end

  # The post at the top of the saved chain replies to one Xtend never saw.
  def missing_parent?
    ancestors
    @missing_parent
  end

  # Your replies first, then the ones from your people, then the rest; each group by likes, then oldest first.
  def replies
    @replies ||= reply_posts.sort_by do |reply|
      group = reply.author_x_id == @owner ? 0 : (people.key?(reply.author_x_id) ? 1 : 2)
      [ group, -reply.like_count.to_i, reply.published_at ]
    end
  end

  def quotes
    @quotes ||= X::SourcePost.where(quoted_x_id: post.x_id, repost: false).order(published_at: :desc).limit(20).to_a
  end

  def marks
    @marks ||= Engagement.where(post_x_id: post.x_id).pluck(:kind).uniq
  end

  def analytics
    return @analytics if defined?(@analytics)
    @analytics = X::PostAnalytic.find_by(post_x_id: post.x_id)
  end

  def author
    people[post.author_x_id] || accounts[post.author_x_id]
  end

  def own?
    post.author_x_id == @owner
  end

  # Lookups for the posts on the page, in the shape the timeline's post partial reads.
  def people
    @people ||= Person.where(x_id: author_ids).includes(:tags).index_by(&:x_id)
  end

  def accounts
    @accounts ||= X::Account.where(x_id: author_ids - people.keys).index_by(&:x_id)
  end

  def quoted
    @quoted ||= X::SourcePost.where(x_id: all_posts.filter_map(&:quoted_x_id)).index_by(&:x_id)
  end

  def sightings
    @sightings ||= X::PostObservation.where(post_x_id: all_posts.map(&:x_id)).group(:post_x_id).count
  end

  def follow_graph
    @follow_graph ||= Follow::Graph.latest
  end

  private

  def reply_posts
    @reply_posts ||= X::SourcePost.where(parent_x_id: post.x_id, repost: false).to_a
  end

  def all_posts
    [ *ancestors, post, *reply_posts, *quotes ]
  end

  def author_ids
    @author_ids ||= begin
      posts = all_posts
      quoted_authors = X::SourcePost.where(x_id: posts.filter_map(&:quoted_x_id)).pluck(:author_x_id)
      (posts.map(&:author_x_id) + posts.filter_map(&:reply_to_x_id) + quoted_authors).uniq
    end
  end
end
