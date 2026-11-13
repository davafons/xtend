# The time spans the mentions reads fully cover, which is what a missing reply to you can be judged against.
# Each read pages back from its run's upper bound, so a run covers from the oldest post it returned up to
# that bound; a finished refresh covers back to its start time even when nothing new arrived. Browser
# captures never count: they show what was on screen, not everything that came in.
class X::MentionCoverage
  def spans
    @spans ||= merge(X::SyncRun.where(dataset: "mentions").where.not(mode: "capture").includes(:x_reads).filter_map { |run| span_for(run) })
  end

  def covers?(from, to)
    spans.any? { |span| span.cover?(from) && span.cover?(to) }
  end

  def covered_until
    spans.map(&:end).max
  end

  private

  def span_for(run)
    returned = run.x_reads.select { |read| read.status == "committed" && read.payload }
      .flat_map { |read| read.payload.fetch("data", []) }.filter_map { |row| row["created_at"] && Time.iso8601(row["created_at"]) }
    start = (Time.iso8601(run.parameters["start_time"]) if run.status == "completed" && run.parameters["start_time"]) || returned.min
    start..run.upper_bound if start && start <= run.upper_bound
  end

  def merge(spans)
    spans.sort_by(&:begin).each_with_object([]) do |span, merged|
      if merged.any? && span.begin <= merged.last.end
        merged[-1] = merged.last.begin..[ merged.last.end, span.end ].max
      else
        merged << span
      end
    end
  end
end
