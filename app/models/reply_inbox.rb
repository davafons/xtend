# Replies people sent you that you haven't answered yet, newest first. A reply counts as answered when you
# replied to it directly, or replied to that person later in the same conversation. You can also set one aside.
# Only collected replies appear, so an empty inbox means nothing is waiting in the data you have.
class ReplyInbox
  Item = Data.define(:event, :post, :liked) do
    delegate :person, :occurred_at, to: :event
    def url = "https://x.com/#{person.handle}/status/#{event.x_id}"
  end

  def initialize(days: 30)
    @since = days.days.ago
  end

  def items
    @items ||= begin
      incoming = ReplyEvent.where(direction: "incoming", dismissed_at: nil, occurred_at: @since..).includes(:person).order(occurred_at: :desc).to_a
      ids = incoming.map(&:x_id)
      owner = Current.workspace.owner_x_id
      answered = ReplyEvent.where(direction: "outgoing", target_x_id: ids).pluck(:target_x_id).to_set
      answered.merge(X::SourcePost.where(author_x_id: owner, parent_x_id: ids).pluck(:parent_x_id))
      posts = X::SourcePost.where(x_id: ids).index_by(&:x_id)
      later = X::SourcePost.where(author_x_id: owner, conversation_x_id: posts.values.filter_map(&:conversation_x_id))
        .pluck(:conversation_x_id, :reply_to_x_id, :published_at)
      liked = Engagement.where(kind: "like", post_x_id: ids).pluck(:post_x_id).to_set
      incoming.reject do |event|
        post = posts[event.x_id]
        answered.include?(event.x_id) ||
          (post&.conversation_x_id && later.any? { |conversation, to, at| conversation == post.conversation_x_id && to == event.person.x_id && at > event.occurred_at })
      end.map { |event| Item.new(event, posts[event.x_id], liked.include?(event.x_id)) }
    end
  end

  def count = items.size
end
