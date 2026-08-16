class ExportsController < ApplicationController
  def show
    export = AccountExport.new(current_user)

    send_data export.to_json,
              filename: export.filename,
              type: "application/json",
              disposition: "attachment"
  end
end
