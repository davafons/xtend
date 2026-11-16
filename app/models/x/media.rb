# A post's photos, videos, and GIFs as x.com's payloads and the X archive describe them, reduced to what Xtend
# draws: the kind, X's image (the photo, or a video's poster frame), the best MP4 for videos and GIFs, alt text,
# and the size. Only X's own media hosts are kept, so a crafted capture can't point the page anywhere else.
module X::Media
  IMAGE = %r{\Ahttps://pbs\.twimg\.com/[\w./-]+\z}
  VIDEO = %r{\Ahttps://video\.twimg\.com/[\w./-]+(\?[\w=&.-]*)?\z}
  KINDS = %w[photo video animated_gif].freeze

  def self.parse(items)
    Array(items).filter_map do |item|
      next unless item.is_a?(Hash) && KINDS.include?(item["type"]) && item["media_url_https"].to_s.match?(IMAGE)
      width, height = size(item)
      variants = Array(item.dig("video_info", "variants")).select { |variant| variant.is_a?(Hash) && variant["content_type"] == "video/mp4" }
      video = variants.max_by { |variant| variant["bitrate"].to_i }&.dig("url")
      { "kind" => item["type"], "image" => item["media_url_https"], "video" => (video if video.to_s.match?(VIDEO)),
        "alt" => (item["ext_alt_text"] if item["ext_alt_text"].is_a?(String)), "width" => width, "height" => height }.compact
    end.presence
  end

  # x.com sends the original size; the archive only lists X's resized copies.
  def self.size(item)
    original = item["original_info"]
    large = item.dig("sizes", "large")
    [ original, large ].each do |info|
      next unless info.is_a?(Hash)
      width, height = (info["width"] || info["w"]).to_i, (info["height"] || info["h"]).to_i
      return [ width, height ] if width.positive? && height.positive?
    end
    nil
  end
end
