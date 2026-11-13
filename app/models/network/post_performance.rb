# How your own top-level posts did, from the counts the capture last saw on each. Counts keep climbing for a
# day or two, so a post only joins the comparisons once its counts were seen at least SETTLED after posting;
# fresher ones are counted separately. Posts without any captured counts are left out, never read as zero.
class Network::PostPerformance
  SETTLED = 2.days
  FORMATS = { "text" => "Text only", "photo" => "Photo", "video" => "Video", "link" => "Link" }.freeze

  Post = Data.define(:record, :format, :people) do
    delegate :x_id, :body, :published_at, :like_count, :repost_count, :reply_count, :view_count, :quote_count, :bookmark_count, :metrics_observed_at, to: :record
    def url = "https://x.com/i/status/#{x_id}"
  end

  Row = Data.define(:format, :posts, :views, :likes, :replies, :people) do
    def label = FORMATS.fetch(format)
  end

  def initialize(since: nil, before: Time.current)
    @since = since
    @before = before
  end

  def posts
    @posts ||= begin
      scope = X::SourcePost.where(author_x_id: Current.workspace.owner_x_id, repost: false, parent_x_id: nil, published_at: @since..@before)
      records = scope.where.not(metrics_observed_at: nil).to_a
      people = ReplyEvent.where(direction: "incoming", target_x_id: records.map(&:x_id)).group(:target_x_id).distinct.count(:person_id)
      records.map { |record| Post.new(record: record, format: format_of(record), people: people.fetch(record.x_id, 0)) }
    end
  end

  def settled
    @settled ||= posts.select { |post| post.metrics_observed_at - post.published_at >= SETTLED }
  end

  def fresh_count = posts.size - settled.size

  def uncounted_count
    X::SourcePost.where(author_x_id: Current.workspace.owner_x_id, repost: false, parent_x_id: nil, published_at: @since..@before, metrics_observed_at: nil).count
  end

  # Medians per format, so one viral post doesn't stand for the rest.
  def by_format
    settled.group_by(&:format).map do |format, group|
      Row.new(format: format, posts: group.size, views: median(group.map(&:view_count)), likes: median(group.map(&:like_count)),
        replies: median(group.map(&:reply_count)), people: group.sum(&:people))
    end.sort_by { |row| -(row.views || -1) }
  end

  def top(limit = 5)
    settled.sort_by { |post| [ -(post.view_count || 0), -(post.like_count || 0) ] }.first(limit)
  end

  def empty?
    posts.empty?
  end

  private

  def format_of(record)
    kinds = record.media_kinds.to_s.split(",")
    if kinds.any? { |kind| kind.include?("video") || kind.include?("gif") } then "video"
    elsif kinds.include?("photo") then "photo"
    elsif record.has_link then "link"
    else "text"
    end
  end

  def median(values)
    values = values.compact.sort
    return if values.empty?
    middle = values.size / 2
    values.size.odd? ? values[middle] : (values[middle - 1] + values[middle]) / 2.0
  end
end
