class FamilyImportsController < ApplicationController
  include StreamExtensions

  before_action :require_admin, only: %i[new create]

  def new
    @import_scope = params[:scope].to_s.presence_in(FamilyImport::IMPORT_SCOPES)
    unless @import_scope
      redirect_to new_import_path, alert: "Choose a valid import type."
      return
    end

    @family_import = FamilyImport.new(import_scope: @import_scope)
    render layout: false
  end

  def index
    @imports = Current.family.family_imports.ordered.limit(10)
    render layout: false
  end

  def create
    @import = Current.family.family_imports.new(family_import_attributes)
    @import.import_file.attach(params.dig(:family_import, :import_file))

    if @import.save
      FamilyDataImportJob.perform_later(@import)
      respond_to do |format|
        format.html { redirect_to imports_path, notice: "Import started. Status will update below." }
        format.turbo_stream {
          stream_redirect_to imports_path, notice: "Import started. Status will update below."
        }
      end
    else
      respond_to do |format|
        format.html { redirect_to imports_path, alert: @import.errors.full_messages.to_sentence }
        format.turbo_stream {
          stream_redirect_to imports_path, alert: @import.errors.full_messages.to_sentence
        }
      end
    end
  end

  private

    def family_import_attributes
      scope = params.dig(:family_import, :import_scope).to_s.presence_in(FamilyImport::IMPORT_SCOPES) || "rules"
      {
        import_scope: scope,
        replace_rules: %w[rules full].include?(scope) && ActiveModel::Type::Boolean.new.cast(params.dig(:family_import, :replace_rules)),
        replace_financial_data: scope == "full" && ActiveModel::Type::Boolean.new.cast(params.dig(:family_import, :replace_financial_data))
      }
    end

    def require_admin
      unless Current.user.admin?
        redirect_to root_path, alert: "Access denied"
      end
    end
end
