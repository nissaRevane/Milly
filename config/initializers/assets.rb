Rails.application.config.assets.version = "1.0"

# Sprockets mounts its asset server at `config.assets.prefix` and *prepends* it to
# the route set, so it sees every /assets request before the router does. The
# default prefix ("/assets") therefore collides with `resources :assets`:
# Sprockets answers anything that is not GET/HEAD with a bare 405 Method Not
# Allowed, which kills create/update/destroy on AssetsController. (GET survives
# only because a Sprockets miss returns 404 with `X-Cascade: pass`.)
# Moving the pipeline out of the way gives /assets back to the application.
Rails.application.config.assets.prefix = "/sprockets"
