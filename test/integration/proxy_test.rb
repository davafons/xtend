require "test_helper"

# Behind Cloudflare Tunnel, requests arrive from cloudflared on a private address with the visitor's IP
# in X-Forwarded-For. Rate limits must count each visitor, not the tunnel.
class ProxyTest < ActionDispatch::IntegrationTest
  setup { sign_out }

  def attempt(ip)
    post session_path, params: { email_address: "owner@example.com", password: "wrong" },
      headers: { "REMOTE_ADDR" => "172.18.0.3", "X-Forwarded-For" => ip }
  end

  test "sign-in limits apply per visitor behind the tunnel" do
    10.times { attempt("203.0.113.7") }
    attempt("203.0.113.7")
    assert_equal "Too many sign-in attempts. Try again in a few minutes.", flash[:alert]
    attempt("198.51.100.9")
    assert_equal "That email address and password don't match.", flash[:alert]
  end
end
