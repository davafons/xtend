class DailySession < ApplicationRecord
  include WorkspaceScoped
  TARGET = 20
  has_many :outreaches, dependent: :nullify

  def self.current
    where(completed_at: nil).order(:created_at).first || where(completed_at: Date.current.all_day).order(completed_at: :desc).first || create!(anchor_day: Date.current)
  rescue ActiveRecord::RecordNotUnique
    find_by!(completed_at: nil)
  end

  def progress
    outreaches.count
  end

  def percent
    [ (progress.to_f / TARGET * 100).round, 100 ].min
  end

  def complete!
    raise ActiveRecord::RecordInvalid, self if progress < TARGET
    update!(completed_at: Time.current)
  end
end
