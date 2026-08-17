class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:firstname, :lastname])
    devise_parameter_sanitizer.permit(:account_update, keys: [:firstname, :lastname])
  end

  # A property_id submitted by a form is only trusted when the bien belongs to the
  # signed-in user: a forged one is dropped here rather than assigned and rejected as a
  # 422. PropertyLinkable stays the model-side backstop for every other write path.
  def scope_property_id(permitted)
    return permitted unless permitted.key?(:property_id)

    permitted[:property_id] = current_user.properties.where(id: permitted[:property_id]).pick(:id)
    permitted
  end

  def render_not_found
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: t("flash.errors.not_found") }
      format.any  { head :not_found }
    end
  end
end
