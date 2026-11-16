# Strict policy for a publicly reachable app. Scripts load only from this origin or carry the per-request nonce
# (the importmap tag gets it automatically). Inline style attributes remain allowed for the palette swatches.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self, :unsafe_inline
    policy.img_src :self, :data, :https
    policy.font_src :self
    # Videos and GIFs in posts play from X's own media host.
    policy.media_src :self, "https://video.twimg.com"
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.frame_ancestors :none
    # Connecting X starts with a form POST that redirects to X's OAuth page.
    policy.form_action :self, "https://x.com", "https://twitter.com"
  end
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
