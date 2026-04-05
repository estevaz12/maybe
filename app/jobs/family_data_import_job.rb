class FamilyDataImportJob < ApplicationJob
  queue_as :default

  MAX_FILE_BYTES = 50.megabytes

  def perform(family_import)
    family_import.update!(status: :processing, error_message: nil)

    unless family_import.import_file.attached?
      family_import.update!(status: :failed, error_message: "No file attached")
      return
    end

    if family_import.import_file.byte_size > MAX_FILE_BYTES
      family_import.update!(status: :failed, error_message: "File is too large (max 50MB)")
      return
    end

    io = StringIO.new(family_import.import_file.download)
    result = Family::DataImporter.new(family_import.family).import_from_zip_io(
      io,
      replace_rules: family_import.replace_rules
    )

    if result.success
      family_import.update!(status: :completed, error_message: nil)
    else
      family_import.update!(status: :failed, error_message: result.error_message)
    end
  rescue => e
    Rails.logger.error "Family import failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    family_import.update!(status: :failed, error_message: e.message)
  end
end
