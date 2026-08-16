Rails.application.config.content_security_policy do |policy|
  policy.default_src :self, :https
  policy.font_src    :self, :https, :data
  policy.img_src     :self, :https, :data
  policy.object_src  :none
  policy.script_src  :self, :https
  policy.style_src   :self, :https, :unsafe_inline
  if Rails.env.development?
    policy.connect_src :self, :https, "http://localhost:3000", "ws://localhost:3000"
  end
end

# `javascript_importmap_tags` emits the importmap and the entry-point import as
# *inline* script tags, which `script_src :self, :https` rejects. Without a nonce
# generator `request.content_security_policy_nonce` is nil, the tags render
# without a nonce and the browser drops them: no Turbo, no Stimulus, no JS at all.
Rails.application.config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
Rails.application.config.content_security_policy_nonce_directives = %w[script-src]
