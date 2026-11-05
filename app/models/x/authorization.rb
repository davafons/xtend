class X::Authorization < ApplicationRecord
  def self.start!
    state = SecureRandom.urlsafe_base64(32)
    attempt = create!(state_digest: Digest::SHA256.hexdigest(state), expires_at: 10.minutes.from_now)
    [attempt, state]
  end

  def self.consume!(id, state)
    attempt = find_by(id: id)
    return false unless attempt && ActiveSupport::SecurityUtils.secure_compare(attempt.state_digest, Digest::SHA256.hexdigest(state.to_s))
    where(id: attempt.id, consumed_at: nil).where("expires_at > ?", Time.current).update_all(consumed_at: Time.current) == 1
  end
end
