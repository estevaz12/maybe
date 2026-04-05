class FamilyImportsController < ApplicationController
  include StreamExtensions

  before_action :require_admin

  def index
    @imports = Current.family.family_imports.ordered.limit(10)
    render layout: false
  end

  def create
    @import = Current.family.family_imports.new(
      replace_rules: ActiveModel::Type::Boolean.new.cast(params.dig(:family_import, :replace_rules))
    )
    @import.import_file.attach(params.dig(:family_import, :import_file))

    if @import.save
      FamilyDataImportJob.perform_later(@import)
      respond_to do |format|
        format.html { redirect_to settings_profile_path, notice: "Import started. Status will update below." }
        format.turbo_stream {
          stream_redirect_to settings_profile_path, notice: "Import started. Status will update below."
        }
      end
    else
      respond_to do |format|
        format.html { redirect_to settings_profile_path, alert: @import.errors.full_messages.to_sentence }
        format.turbo_stream {
          stream_redirect_to settings_profile_path, alert: @import.errors.full_messages.to_sentence
        }
      end
    end
  end

  private

    def require_admin
      unless Current.user.admin?
        redirect_to root_path, alert: "Access denied"
      end
    end
end
