# Replies people sent you that you haven't answered yet, newest first. A reply counts as answered when you
# replied to it directly, or replied to that person later in the same conversation. You can also set one aside.
# Only collected replies appear, so an empty inbox means nothing is waiting in the data you have.
#
# Every first reply gets an answer. A follow-up (they replied, you answered, they replied to your answer) may
# end the exchange, so follow-ups are listed apart and don't count as waiting. A reply to your own outreach
# reply is not a follow-up: it's their first answer to you.
class ReplyInbox
  Item = Data.define(:event, :post, :liked) do
    delegate :person, :occurred_at, to: :event
    def url = "https://x.com/#{person.handle}/status/#{event.x_id}"
  end

  def initialize(days: 30, follow_ups: false)
    @since = days.days.ago
    @follow_ups = follow_ups
  end

  def items
    @items ||= unanswered.partition { |item| follow_up_ids.include?(item.event.x_id) }.then { |follow, waiting| @follow_ups ? follow : waiting }
  end

  def count = items.size
  def waiting_count = unanswered.count { |item| !follow_up_ids.include?(item.event.x_id) }
  def follow_up_count = unanswered.count { |item| follow_up_ids.include?(item.event.x_id) }

  private
    # Replies aimed at one of your posts that itself answered a reply from them.
    def follow_up_ids
      @follow_up_ids ||= begin
        events = unanswered.map(&:event)
        targets = events.map(&:target_x_id)
        parents = X::SourcePost.where(author_x_id: Current.workspace.owner_x_id, x_id: targets).pluck(:x_id, :parent_x_id).to_h
        parents.merge!(ReplyEvent.where(direction: "outgoing", x_id: targets).pluck(:x_id, :target_x_id).to_h) { |_, post, event| post || event }
        answered_replies = ReplyEvent.where(direction: "incoming", x_id: parents.values.compact).pluck(:x_id).to_set
        events.select { |event| answered_replies.include?(parents[event.target_x_id]) }.map(&:x_id).to_set
      end
    end

    def unanswered
      @unanswered ||= begin
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
end
